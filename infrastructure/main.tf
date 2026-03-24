#Defining the cloud provider
provider "aws" {
  region = "us-east-1"
}

#Get the current AWS account ID to make our S3 buckets globally unique 

data "aws_caller_identity" "current" {}

locals {
 account_id = data.aws_caller_identity.current.account_id
}

#Creating medallion s3 buckets

resource "aws_s3_bucket" "datalake" {
    for_each = toset([ "bronze", "silver", "gold" ])

    bucket = "ecom-data-lake-${each.key}-prod-${local.account_id}"
}

resource "aws_kinesis_stream" "clickstream" {
  name             = "ecom-clickstream-dev"
  shard_count      = 1
  retention_period = 24

}


resource "aws_iam_role" "firehose_role" {
  name = "firehose_delivery_role"


  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      },
    ]
  })

}

resource "aws_iam_role_policy" "firehose_policy" {
  name = "firehose_s3_policy"
  role = aws_iam_role.firehose_role.id


  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
        Effect   = "Allow"
        Resource = [aws_s3_bucket.datalake["bronze"].arn, "${aws_s3_bucket.datalake["bronze"].arn}/*" ] 
      },
      {
        Action = ["kinesis:GetShardIterator", "kinesis:GetRecords", "kinesis:DescribeStream"]
        Effect   = "Allow"
        Resource = aws_kinesis_stream.clickstream.arn
      },
    ]
  })
}


resource "aws_kinesis_firehose_delivery_stream" "extended_s3_stream" {
  name        = "ecom-stream-to-bronze"
  destination = "extended_s3"
  
  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.clickstream.arn
    role_arn = aws_iam_role.firehose_role.arn
  }
  
  extended_s3_configuration {
    bucket_arn = aws_s3_bucket.datalake["bronze"].arn
    role_arn = aws_iam_role.firehose_role.arn


    buffering_size = 1
    buffering_interval = 60

    prefix = "clickstream/ingest_date=!{timestamp:yyyy-MM-dd}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/"
  }
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "ecom-data-artifacts-dev-${local.account_id}"

}

resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "scripts/bronze_to_silver.py"
  source = "../src/jobs/bronze_to_silver.py"

  etag = filemd5("../src/jobs/bronze_to_silver.py")
}

resource "aws_iam_role" "glue_role" {
  name = "ecom_glue_role"


  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "glue.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_policy" {
  name = "ecom_glue_policy"
  role = aws_iam_role.glue_role.id


  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Effect   = "Allow"
        Resource = [aws_s3_bucket.datalake["bronze"].arn, 
        "${aws_s3_bucket.datalake["bronze"].arn}/*",
        aws_s3_bucket.datalake["silver"].arn,
        "${aws_s3_bucket.datalake["silver"].arn}/*",
        aws_s3_bucket.artifacts.arn,
        "${aws_s3_bucket.artifacts.arn}/*"
        
        ]
      },
    ]
  })
}


resource "aws_glue_job" "bronze_to_silver" {
    name = "ecom_bronze_to_silver"
    role_arn = aws_iam_role.glue_role.arn
    glue_version      = "5.0"
    number_of_workers = 2
    worker_type       = "G.1X"

    command {
    script_location = "s3://${aws_s3_bucket.artifacts.id}/scripts/bronze_to_silver.py"
    name            = "glueetl"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language" = "python"
    "--BRONZE_BUCKET" = aws_s3_bucket.datalake["bronze"].bucket
    "--SILVER_BUCKET" = aws_s3_bucket.datalake["silver"].bucket
  }

}


resource "aws_glue_catalog_database" "ecom_db" {
  name = "ecom_analytics_dev"
}

resource "aws_glue_crawler" "silver_crawler" {
  database_name = aws_glue_catalog_database.ecom_db.name
  name          = "ecom_silver_crawler"
  role          = aws_iam_role.glue_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.datalake["silver"].bucket}/clickstream_cleaned/"
  }
}

resource "aws_s3_bucket" "athena_results" {
  bucket = "ecom-athena-results-dev-${local.account_id}"
}


resource "aws_athena_workgroup" "analytics" {
  name = "ecom_analytics_wg"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/output/"

    }
  }
}


resource "aws_iam_role" "redshift_s3_role" {
  name = "ecom_redshift_s3_read"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "redshift.amazonaws.com"
        }
      },
    ]
  })

}


resource "aws_iam_role_policy" "redshift_s3_policy" {
  name = "redshift_read_gold_bucket"
  role = aws_iam_role.redshift_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["s3:GetObject", "s3:ListBucket"]
        Effect   = "Allow"
        Resource = [ aws_s3_bucket.datalake["gold"].arn,
                     "${aws_s3_bucket.datalake["gold"].arn}/*"
         ]
      },
    ]
  })
}

resource "aws_redshift_cluster" "data_warehouse" {
  cluster_identifier = "ecom-gold-warehouse"
  database_name      = "ecom_gold"
  master_username    = "adminuser"
  master_password    = "Imran123"
  node_type          = "ra3.large"
  cluster_type       = "single-node"
  iam_roles          = [aws_iam_role.redshift_s3_role.arn]
  publicly_accessible = true
  skip_final_snapshot = true
}


resource "aws_s3_object" "glue_script_gold" {
  bucket = aws_s3_bucket.artifacts.bucket
  key    = "scripts/silver_to_gold.py"
  source = "../src/jobs/silver_to_gold.py"


  etag = filemd5("../src/jobs/silver_to_gold.py")
}

resource "aws_glue_job" "silver_to_gold" {
  name = "ecom_silver_to_gold"
  role_arn = aws_iam_role.glue_role.arn
  glue_version = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2

  command {
    script_location = "s3://${aws_s3_bucket.artifacts.bucket}/scripts/silver_to_gold.py"
    name            = "glueetl"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"    =   "python"
    "--SILVER_BUCKET"   =   aws_s3_bucket.datalake["silver"].bucket
    "--GOLD_BUCKET"     =   aws_s3_bucket.datalake["gold"].bucket
  }


}