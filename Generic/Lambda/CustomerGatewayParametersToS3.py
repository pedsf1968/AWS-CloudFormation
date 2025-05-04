import boto3
import json

bucket =  "hawkfund-cloudformation"
bucket_key = "90_SiteToSiteVpn/Data.json"
parameter_key = "eu-central-1:ANS:dev:EC2:CustomerGateway:Test"
customer_gateway_id = "cgw-036c50cebe8717c74"
data = {}
response_data = {}

s3_client = boto3.client('s3')
ec2_client = boto3.client('ec2', region_name='eu-central-1')

def get_node(my_dict, paths) -> dict:
  for key in paths:
      my_dict = my_dict.setdefault(key)
  return my_dict   

value = None

try:
  # Read data file from s3
  s3_response = s3_client.get_object(
      Bucket=bucket,
      Key=key
  )
  json_data = s3_response["Body"].read().decode('utf-8')
  data = json.loads(json_data)
except Exception as err:
  print("WARNING: No file present on the s3 Bucket, starting a new file!")

try:
  # Get Customer Gateway parameters
  customer_gateway_data = ec2_client.describe_customer_gateways(CustomerGatewayIds=[ customer_gateway_id ])

  paths = parameter_key.split(":")
  last_index = paths.pop()

  get_node(data, paths)['BgpAsn'] = customer_gateway_data['CustomerGateways'][0]['BgpAsn']
  get_node(data, paths)['CustomerGatewayId'] = customer_gateway_data['CustomerGateways'][0]['CustomerGatewayId']
  get_node(data, paths)['IpAddress'] = customer_gateway_data['CustomerGateways'][0]['IpAddress']
  get_node(data, paths)['State'] = customer_gateway_data['CustomerGateways'][0]['State']
  get_node(data, paths)['Type'] = customer_gateway_data['CustomerGateways'][0]['Type']
  print(data)
except Exception as err:
  print("WARNING: Wrong Customer GatewayID: ", customer_gateway_id)

try:
  # Wrote data file from s3
  s3_response = s3_client.put_object(
      Body=bytes(json.dumps(data).encode('UTF-8')),
      Bucket=bucket,
      Key=key
  )
  response_data['BgpAsn'] = customer_gateway_data['CustomerGateways'][0]['BgpAsn']
  response_data['CustomerGatewayId'] = customer_gateway_data['CustomerGateways'][0]['CustomerGatewayId']
  response_data['IpAddress'] = customer_gateway_data['CustomerGateways'][0]['IpAddress']
  response_data['State'] = customer_gateway_data['CustomerGateways'][0]['State']
  response_data['Type'] = customer_gateway_data['CustomerGateways'][0]['Type']
  print(response_data)
except Exception as err:
  print("ERROR: Can't save to s3 Bucket")
