**Clickstream Data Pipeline using AWS & Terraform**
**Overview:**
This project implements an end-to-end clickstream data pipeline on AWS, designed using the medallion architecture (Bronze → Silver → Gold) to enable scalable, reliable, and analytics-ready data processing. The pipeline ingests raw clickstream data, performs multi-stage transformations using Spark, and delivers curated datasets for downstream analytics and dashboarding.

**Architecture:**
The pipeline follows a layered approach:
Bronze Layer (Raw Data):
Raw clickstream data is ingested into Amazon S3 in its original format. This layer ensures data traceability and supports reprocessing.
Silver Layer (Cleaned Data):
Data is processed using AWS Glue (PySpark jobs) to perform:
Data cleaning:
Schema enforcement
Basic transformations
The refined data is stored in a Silver S3 bucket.
Gold Layer (Business Aggregates):
Further transformations and aggregations are applied using Glue Spark jobs to generate business-level metrics such as:
User sessions
Click counts
Conversion metrics
The output is stored in the Gold S3 bucket.

**Data Warehousing:**
Curated Gold data is loaded into Amazon Redshift, where aggregation tables are created to support fast querying and dashboarding use cases.

**Infrastructure as Code:**
All AWS resources (S3 buckets, Glue jobs, IAM roles, Redshift cluster, etc.) are provisioned and managed using Terraform, ensuring:
Reproducibility
Scalability
Version-controlled infrastructure
