import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, to_timestamp, to_date

# 1. Initialize the Glue and Spark Contexts
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'BRONZE_BUCKET', 'SILVER_BUCKET'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Get the bucket names passed dynamically from Terraform
BRONZE_PATH = f"s3://{args['BRONZE_BUCKET']}/clickstream/"
SILVER_PATH = f"s3://{args['SILVER_BUCKET']}/clickstream_cleaned/"

print(f"Reading raw data from: {BRONZE_PATH}")

# 2. Extract: Read the raw JSON data from the Bronze S3 bucket
# Spark automatically infers the schema from the JSON!
bronze_df = spark.read.json(BRONZE_PATH)

# 3. Transform: Clean the data
silver_df = bronze_df \
    .dropDuplicates(["event_id"]) \
    .withColumn("event_timestamp", to_timestamp(col("event_timestamp"))) \
    .withColumn("event_date", to_date(col("event_timestamp")))

# 4. Load: Write the cleaned data to the Silver bucket as Parquet
# We partition by 'event_date' to make future SQL queries incredibly fast
print(f"Writing cleaned data to: {SILVER_PATH}")
silver_df.write \
    .mode("overwrite") \
    .partitionBy("event_date") \
    .format("parquet") \
    .save(SILVER_PATH)

job.commit()
print("Bronze to Silver ETL Job Complete!")