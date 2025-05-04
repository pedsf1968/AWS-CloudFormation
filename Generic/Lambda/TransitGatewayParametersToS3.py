import boto3
import json

bucket =  "hawkfund-cloudformation"
bucket_key = "71_TransitGatewayRestrictedRouting"
bucket_object = "Data.json"
parameter_key = "eu-west-3:ANS:dev:EC2:TransitGateway:Test"
transit_gateway_id = "tgw-062d6946bc4482447"
key = bucket_key + "/" + bucket_object
data = {}
response_data = {}

s3_client = boto3.client('s3')
ec2_client = boto3.client('ec2')

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
  print("json_data: ", json_data)
  data = json.loads(json_data)
except Exception as err:
  print("WARNING: No file present on the s3 Bucket, starting a new file!")

try:
  # Get Transit Customer Gateway parameters
  transit_gateway_data = ec2_client.describe_transit_gateways(TransitGatewayIds=[ transit_gateway_id ])
  # print("transit_gateway_data: ", transit_gateway_data)
  print("data: ", data)
  paths = parameter_key.split(":")
  print(paths)
  last_index = paths.pop()
 
  get_node(data, paths)['TransitGatewayId'] = transit_gateway_data['TransitGateways'][0]['TransitGatewayId']
  # get_node(data, paths)['TransitGatewayArn'] = transit_gateway_data['TransitGateways'][0]['TransitGatewayArn']
  # get_node(data, paths)['State'] = transit_gateway_data['TransitGateways'][0]['State']
  # get_node(data, paths)['OwnerId'] = transit_gateway_data['TransitGateways'][0]['OwnerId']
  # get_node(data, paths)['Description'] = transit_gateway_data['TransitGateways'][0]['Description']
  # get_node(data, paths)['AmazonSideAsn'] = transit_gateway_data['TransitGateways'][0]['Options']['AmazonSideAsn']
  # get_node(data, paths)['AutoAcceptSharedAttachments'] = transit_gateway_data['TransitGateways'][0]['Options']['AutoAcceptSharedAttachments']
  # get_node(data, paths)['DefaultRouteTableAssociation'] = transit_gateway_data['TransitGateways'][0]['Options']['DefaultRouteTableAssociation']
  # get_node(data, paths)['AssociationDefaultRouteTableId'] = transit_gateway_data['TransitGateways'][0]['Options']['AssociationDefaultRouteTableId']
  # get_node(data, paths)['DefaultRouteTablePropagation'] = transit_gateway_data['TransitGateways'][0]['Options']['DefaultRouteTablePropagation']
  # get_node(data, paths)['PropagationDefaultRouteTableId'] = transit_gateway_data['TransitGateways'][0]['Options']['PropagationDefaultRouteTableId']
  # get_node(data, paths)['VpnEcmpSupport'] = transit_gateway_data['TransitGateways'][0]['Options']['VpnEcmpSupport']
  # get_node(data, paths)['DnsSupport'] = transit_gateway_data['TransitGateways'][0]['Options']['DnsSupport']
  # get_node(data, paths)['SecurityGroupReferencingSupport'] = transit_gateway_data['TransitGateways'][0]['Options']['SecurityGroupReferencingSupport']
  # get_node(data, paths)['MulticastSupport'] = transit_gateway_data['TransitGateways'][0]['Options']['MulticastSupport']
  print(data)
except Exception as err:
  print(err)
  print("WARNING: Wrong Transit GatewayID: ", transit_gateway_id)

try:
  # Wrote data file from s3
  s3_response = s3_client.put_object(
      Body=bytes(json.dumps(data).encode('UTF-8')),
      Bucket=bucket,
      Key=key
  )

except Exception as err:
  print("ERROR: Can't save to s3 Bucket")
