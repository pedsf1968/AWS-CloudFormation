import boto3
import json

bucket =  "hawkfund-cloudformation"
bucketKey = "90_SiteToSiteVpn/Data.json"
parameterKey = "eu-west-3:ANS:dev:EC2:VPC:D"

  

client = boto3.client('s3')

def get_node(my_dict, paths) -> dict:
  for key in paths:
      my_dict = my_dict.setdefault(key)
  return my_dict   

value = None

try:
  # Read file from s3
  response = client.get_object(
      Bucket=bucket,
      Key=bucketKey
  )
  json_data = response["Body"].read().decode('utf-8')
  data = json.loads(json_data)
  paths = parameterKey.split(":")
  last_index = paths.pop()

  value = get_node(data, paths)[last_index]
except KeyError:
  print("ERROR: Bad key!")
except Exception as err:
  print("ERROR: No file!")

print(value)

