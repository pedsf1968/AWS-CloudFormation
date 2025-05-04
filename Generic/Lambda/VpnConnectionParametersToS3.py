import boto3
import json

bucket =  "hawkfund-cloudformation"
bucket_key = "90_SiteToSiteVpn/Data.json"
parameter_key = "eu-central-1:ANS:dev:EC2:VPNConnection:Test"
vpn_connection_id = "vpn-04655dafec24a0188"
  

s3_client = boto3.client('s3')
ec2_client = boto3.client('ec2', region_name='eu-central-1')

def get_node(my_dict, paths) -> dict:
  for key in paths:
      my_dict = my_dict.setdefault(key)
  return my_dict

value = None

vpn_connection_data = ec2_client.describe_vpn_connections(VpnConnectionIds=[ vpn_connection_id ])

try:
  # Read file from s3
  s3_response = s3_client.get_object(
      Bucket=bucket,
      Key=bucket_key
  )
  json_data = s3_response["Body"].read().decode('utf-8')
  data = json.loads(json_data)
  paths = parameter_key.split(":")
  last_index = paths.pop()

  get_node(data, paths)['Category'] = vpn_connection_data['VpnConnections'][0]['Category']
  get_node(data, paths)['CustomerGatewayId'] = vpn_connection_data['VpnConnections'][0]['CustomerGatewayId']
  get_node(data, paths)['GatewayAssociationState'] = vpn_connection_data['VpnConnections'][0]['GatewayAssociationState']
  get_node(data, paths)['State'] = vpn_connection_data['VpnConnections'][0]['State']
  get_node(data, paths)['Type'] = vpn_connection_data['VpnConnections'][0]['Type']
  get_node(data, paths)['Type'] = vpn_connection_data['VpnConnections'][0]['Type']
  get_node(data, paths)['VpnConnectionId'] = vpn_connection_data['VpnConnections'][0]['VpnConnectionId']
  get_node(data, paths)['VpnGatewayId'] = vpn_connection_data['VpnConnections'][0]['VpnGatewayId']
  get_node(data, paths)['EnableAcceleration'] = vpn_connection_data['VpnConnections'][0]['Options']['EnableAcceleration']
  get_node(data, paths)['StaticRoutesOnly'] = vpn_connection_data['VpnConnections'][0]['Options']['StaticRoutesOnly']
  get_node(data, paths)['LocalIpv4NetworkCidr'] = vpn_connection_data['VpnConnections'][0]['Options']['LocalIpv4NetworkCidr']
  get_node(data, paths)['RemoteIpv4NetworkCidr'] = vpn_connection_data['VpnConnections'][0]['Options']['RemoteIpv4NetworkCidr']
  get_node(data, paths)['OutsideIpAddressType'] = vpn_connection_data['VpnConnections'][0]['Options']['OutsideIpAddressType']
  get_node(data, paths)['TunnelInsideIpVersion'] = vpn_connection_data['VpnConnections'][0]['Options']['TunnelInsideIpVersion']
  get_node(data, paths)['OutsideIpAddress1'] = vpn_connection_data['VpnConnections'][0]['Options']['TunnelOptions'][0]['OutsideIpAddress']
  get_node(data, paths)['TunnelInsideCidr1'] = vpn_connection_data['VpnConnections'][0]['Options']['TunnelOptions'][0]['TunnelInsideCidr']
  get_node(data, paths)['PreSharedKey1'] = vpn_connection_data['VpnConnections'][0]['Options']['TunnelOptions'][0]['PreSharedKey']
  get_node(data, paths)['OutsideIpAddress2'] = vpn_connection_data['VpnConnections'][0]['Options']['TunnelOptions'][1]['OutsideIpAddress']
  get_node(data, paths)['TunnelInsideCidr2'] = vpn_connection_data['VpnConnections'][0]['Options']['TunnelOptions'][1]['TunnelInsideCidr']
  get_node(data, paths)['PreSharedKey2'] = vpn_connection_data['VpnConnections'][0]['Options']['TunnelOptions'][1]['PreSharedKey']

  print(data)
  s3_response = s3_client.put_object(
      Body=bytes(json.dumps(data).encode('UTF-8')),
      Bucket=bucket,
      Key=bucket_key
  )
except KeyError:
  print("ERROR: Bad key!")
except Exception as err:
  print("ERROR: No file!")


