import boto3
import json
import logging
from botocore.exceptions import NoCredentialsError, PartialCredentialsError, ClientError

# Constants
bucket = "hawkfund-cloudformation"
bucket_key = "54_VPCGatewayEndpointForS3/Data.json"
parameter_key = "eu-west-3:ANS:dev:EC2:SecurityGroup:Test"
security_group_id = "sg-0e477c53ee4493095"

# Initialize AWS clients
s3_client = boto3.client('s3')
ec2_client = boto3.client('ec2')

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Helper function to navigate through a nested dictionary
def get_node(my_dict, paths) -> dict:
    for key in paths:
        my_dict = my_dict.setdefault(key, {})
    return my_dict

def update_security_group_in_s3():
    try:
        # Retrieve security group data
        security_group_data = ec2_client.describe_security_groups(GroupIds=[security_group_id])
        print("security_group_data: ", security_group_data)

        # Read data file from S3
        s3_response = s3_client.get_object(Bucket=bucket, Key=bucket_key)
        json_data = s3_response["Body"].read().decode('utf-8')
        data = json.loads(json_data)
        logger.info("Data retrieved from S3: %s", data)

        # Split the parameter key into paths
        paths = parameter_key.split(":")
        last_index = paths.pop()

        # Update the JSON data with the security group ID
        get_node(data, paths)[last_index] = security_group_data['SecurityGroups'][0]
        logger.info("Updated data: %s", data)

        # Write the updated data back to S3
        s3_client.put_object(
            Body=bytes(json.dumps(data).encode('UTF-8')),
            Bucket=bucket,
            Key=bucket_key
        )
        logger.info("Data successfully updated in S3.")

    except (NoCredentialsError, PartialCredentialsError):
        logger.error("AWS credentials not available.")
    except ClientError as e:
        if e.response['Error']['Code'] == "NoSuchBucket":
            logger.error("The specified bucket does not exist.")
        elif e.response['Error']['Code'] == "NoSuchKey":
            logger.error("The specified key does not exist.")
        else:
            logger.error("Client error: %s", e)
    except KeyError:
        logger.error("Bad key in the JSON data.")
    except json.JSONDecodeError:
        logger.error("Error decoding JSON data.")
    except Exception as err:
        logger.error("An unexpected error occurred: %s", err)

if __name__ == "__main__":
    update_security_group_in_s3()
