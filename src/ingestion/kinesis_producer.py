import boto3
import json
import time
import random
import uuid
from datetime import datetime, timezone

# Connect to AWS Kinesis using your configured credentials
kinesis = boto3.client('kinesis', region_name='us-east-1')
STREAM_NAME = 'ecom-clickstream-dev'

EVENT_TYPES = ["page_view", "add_to_cart", "remove_from_cart", "checkout", "purchase"]

def generate_event():
    """Simulates a user clicking on the website."""
    return {
        "event_id": str(uuid.uuid4()),
        "user_id": f"user_{random.randint(1, 100)}",
        "event_type": random.choice(EVENT_TYPES),
        "item_id": f"item_{random.randint(1, 50)}",
        "price": round(random.uniform(5.0, 150.0), 2),
        "event_timestamp": datetime.now(timezone.utc).isoformat()
    }

def stream_data():
    print(f"🚀 Starting to stream data to {STREAM_NAME}...")
    print("Press Ctrl+C to stop.")
    
    try:
        while True:
            event = generate_event()
            
            # Blast the JSON event into the Kinesis Stream
            response = kinesis.put_record(
                StreamName=STREAM_NAME,
                Data=json.dumps(event),
                PartitionKey=event['user_id']
            )
            
            print(f"Sent: {event['event_type']} by {event['user_id']} | Shard ID: {response['ShardId']}")
            
            # Pause for a fraction of a second to simulate realistic web traffic
            time.sleep(random.uniform(0.2, 0.8))
            
    except KeyboardInterrupt:
        print("\n🛑 Streaming stopped.")
    except Exception as e:
        print(f"\n❌ Error: {e}")

if __name__ == "__main__":
    stream_data()