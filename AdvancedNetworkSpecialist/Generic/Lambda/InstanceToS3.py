import boto3
import json
import os
import logging
from botocore.exceptions import ClientError
from datetime import datetime
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load configuration from environment variables
Bucket = os.getenv('S3_BUCKET', 'hawkfund-cloudformation')
BucketKey = os.getenv('S3_BUCKET_KEY', '54_VPCGatewayEndpointForS3')
BucketObject = os.getenv('S3_BUCKET_OBJECT', 'Data.json')
Value = os.getenv('EC2_INSTANCE_ID', 'i-0514784b2571f9c1f')
Key = os.getenv('PARAMETER_KEY', 'eu-west-3:ANS:dev:EC2:Instance:Application')
RegionName = os.getenv('AWS_REGION', 'eu-west-3')

s3_client = boto3.client('s3')
ec2_client = boto3.client('ec2', region_name=RegionName)

def get_node(my_dict: Dict[str, Any], paths: list) -> Dict[str, Any]:
    """Navigate through the dictionary using the given paths."""
    for key in paths:
        my_dict = my_dict.setdefault(key, {})
    return my_dict

def fetch_resource_data(resource_id: str) -> Dict[str, Any]:
    """Fetch instance data from EC2 with retry logic."""
    try:
        response = ec2_client.describe_instances(InstanceIds=[resource_id])
        return response['Reservations'][0]['Instances'][0]
    except ClientError as err:
        logger.warning(f"Wrong InstanceID: {resource_id}. Error: {err}")
        raise err

def json_serial(obj: Any) -> str:
    """Helper function to serialize datetime objects."""
    if isinstance(obj, datetime):
        return obj.isoformat()
    raise TypeError("Type not serializable")

def read_s3_object(bucket: str, key: str) -> Dict[str, Any]:
    """Read JSON data from S3 bucket with retry logic."""
    try:
        s3_response = s3_client.get_object(Bucket=bucket, Key=key)
        return json.loads(s3_response["Body"].read().decode('utf-8'))
    except ClientError as err:
        logger.error(f"Error reading from S3 bucket {bucket}. Error: {err}")
        return {}

def write_s3_object(bucket: str, key: str, data: Dict[str, Any]) -> None:
    """Write JSON data to S3 bucket with retry logic."""
    try:
        s3_client.put_object(
            Body=bytes(json.dumps(data, default=json_serial).encode('UTF-8')),
            Bucket=bucket,
            Key=key
        )
    except ClientError as err:
        logger.error(f"Can't write to S3 bucket {bucket}. Error: {err}")
        raise err

def lambda_handler(bucket: str, bucket_key: str, bucket_object: str, parameter_key: str, resource_id: str) -> None:
    key = f"{bucket_key}/{bucket_object}"
    response_data = {}

    try:
        # Fetch resource data
        resource_data = fetch_resource_data(resource_id)

        # Read data file from S3
        s3_data = read_s3_object(bucket, key)
        # Split the parameter key into paths
        paths = parameter_key.split(":")
        last_index = paths.pop()

        # Update the JSON data with the instance information
        get_node(s3_data, paths)[last_index] = resource_data

        # Write the updated data back to S3
        write_s3_object(bucket, key, s3_data)

        response_data[last_index] = resource_data
    except Exception as err:
        logger.error("An error occurred during processing", exc_info=True)
        response_data["Data"] = str(err)

    logger.info(response_data)

def main() -> None:
    lambda_handler(
        bucket=Bucket,
        bucket_key=BucketKey,
        bucket_object=BucketObject,
        parameter_key=Key,
        resource_id=Value
    )

if __name__ == "__main__":
    main()
