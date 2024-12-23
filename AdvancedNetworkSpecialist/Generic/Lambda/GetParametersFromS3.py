import boto3
import cfnresponse
import json
import time

s3 = boto3.resource('s3')

def lambda_handler(event, context):
  responseData  = {}
  bucket =  event["ResourceProperties"]["Bucket"]
  bucketKey = event["ResourceProperties"]["BucketKey"]
  parameterKey = event["ResourceProperties"]["Key"]
  try:
    obj = s3.Object(bucket, bucketKey)
    data = obj.get()['Body'].read().decode('utf-8')
    responseData["Value"] = json.loads(data)[parameterKey]
    cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData)                            
  except Exception as err:
    responseData['Data'] = str(err)
    cfnresponse.send(event, context, cfnresponse.FAILED, responseData)
