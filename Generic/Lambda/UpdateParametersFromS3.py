import boto3
import json

bucket =  "hawkfund-cloudformation"
bucket_key = "90_SiteToSiteVpn/Data.json"
parameter_key = "eu-west-3:ANS:dev:EC2:VPC:DC:toto"
parameter_value = "titi"

# Initialise client type
s3_client = boto3.client('s3')

def get_node(my_dict, paths) -> dict:
    for key in paths:
        my_dict = my_dict.setdefault(key, {})
    return my_dict

try:
    # Read file from s3
    response = s3_client.get_object(
        Bucket=bucket,
        Key=bucket_key
    )
    print(response)
    json_data = response["Body"].read().decode('utf-8')
    data = json.loads(json_data)
except Exception as err:
    print("ERROR: No file")
    data = {}

paths = parameter_key.split(":")
last_index = paths.pop()

# Change data value for specified key
get_node(data, paths)[last_index] = parameter_value
print(data)
# Write file from s3
response = s3_client.put_object(
    Body=bytes(json.dumps(data).encode('UTF-8')),
    Bucket=bucket,
    Key=bucket_key
)