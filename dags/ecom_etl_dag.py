from airflow import DAG
from airflow.providers.amazon.aws.operators.glue import GlueJobOperator
from airflow.providers.amazon.aws.operators.redshift_data import RedshiftDataOperator
from datetime import datetime, timedelta

# 1. Define Default Settings for the Pipeline
default_args = {
    'owner': 'data_engineering_team',
    'depends_on_past': False,
    'start_date': datetime(2026, 3, 17),
    'retries': 2, # If a job fails, Airflow will wait and try again up to 2 times
    'retry_delay': timedelta(minutes=5),
}

# 2. Initialize the DAG (Scheduled to run daily at midnight UTC)
with DAG(
    'ecommerce_end_to_end_pipeline',
    default_args=default_args,
    schedule_interval='@daily',
    catchup=False,
    tags=['production', 'ecom', 'daily']
) as dag:

    # TASK 1: Run the Bronze to Silver Cleaning Job
    bronze_to_silver = GlueJobOperator(
        task_id='clean_raw_data',
        job_name='ecom_bronze_to_silver',
        region_name='us-east-1',
        wait_for_completion=True # Airflow will pause here until Glue is 100% finished
    )

    # TASK 2: Run the Silver to Gold Aggregation Job
    silver_to_gold = GlueJobOperator(
        task_id='aggregate_business_metrics',
        job_name='ecom_silver_to_gold',
        region_name='us-east-1',
        wait_for_completion=True
    )

    # TASK 3: Copy the Gold Data from S3 into Amazon Redshift
    # We use the IAM role we created in Terraform to authorize the copy
    # IMPORTANT: Update the Account ID in the iam_role string to match yours!
    copy_to_redshift_sql = """
        COPY daily_metrics 
        FROM 's3://ecom-data-lake-gold-prod-YOUR_ACCOUNT_ID/daily_metrics/' 
        IAM_ROLE 'arn:aws:iam::YOUR_ACCOUNT_ID:role/ecom_redshift_s3_read' 
        FORMAT AS PARQUET;
    """

    load_redshift = RedshiftDataOperator(
        task_id='load_gold_to_data_warehouse',
        cluster_identifier='ecom-gold-warehouse',
        database='ecom_gold',
        db_user='adminuser',
        sql=copy_to_redshift_sql,
        region_name='us-east-1',
        await_result=True
    )

    # 3. Define the Order of Operations (The Dependency Chain)
    # This is the magic of Airflow. It ensures Task 2 won't start until Task 1 succeeds.
    bronze_to_silver >> silver_to_gold >> load_redshift