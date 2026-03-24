import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import count, sum as _sum, col

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'SILVER_BUCKET', 'GOLD_BUCKET'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

SILVER_PATH = f"s3://{args['SILVER_BUCKET']}/clickstream_cleaned/"
GOLD_PATH = f"s3://{args['GOLD_BUCKET']}/daily_metrics/"

print(f"Reading Silver data from: {SILVER_PATH}")
silver_df = spark.read.parquet(SILVER_PATH)

# ==========================================
# GOLD TRANSFORMATION: Business Aggregations
# ==========================================

# 1. Daily Event Counts (How many of each event happened per day?)
daily_events_df = silver_df.groupBy("event_date", "event_type") \
    .agg(count("event_id").alias("total_events"))

# 2. Daily Revenue (Sum of price for 'purchase' events)
daily_revenue_df = silver_df.filter(col("event_type") == "purchase") \
    .groupBy("event_date") \
    .agg(_sum("price").alias("daily_revenue"))

# Join the metrics together into one Gold table
gold_df = daily_events_df.join(daily_revenue_df, on="event_date", how="left")

# Write to the Gold S3 Bucket
print(f"Writing Gold aggregated data to: {GOLD_PATH}")
gold_df.write \
    .mode("overwrite") \
    .format("parquet") \
    .save(GOLD_PATH)

job.commit()
print("Silver to Gold Aggregation Complete!")