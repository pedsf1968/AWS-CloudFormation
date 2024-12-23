import boto3
import json

bucket =  "hawkfund-cloudformation"
bucketKey = "90_SiteToSiteVpn/Data.json"
parameterKey = "eu-west-3-ANS-dev-DC-VpcId"
parameterValue = "titi"

# Initialise client type
client = boto3.client('s3')
try:
    # Read file from s3
    response = client.get_object(
        Bucket=bucket,
        Key=bucketKey
    )
    print(response)
    json_data = response["Body"].read().decode('utf-8')
    data = json.loads(json_data)             
except Exception as err:
    print("ERROR: No file")
    data = {}

# Change data value for specified key
data[parameterKey] = parameterValue

# Write file from s3
response = client.put_object(
    Body=bytes(json.dumps(data).encode('UTF-8')),
    Bucket=bucket,
    Key=bucketKey
)