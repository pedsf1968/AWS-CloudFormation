# Initialise
## Create directory
[cloudshell-user@ip-10-2-84-35 s3-module]$ mkdir s3-module
[cloudshell-user@ip-10-2-84-35 s3-module]$ cd s3-module

## Install cfn cli
[cloudshell-user@ip-10-2-84-35 s3-module]$ sudo yum install pip3
[cloudshell-user@ip-10-2-84-35 s3-module]$ pip3 install cloudformation-cli cloudformation-cli-java-plugin cloudformation-cli-go-plugin cloudformation-cli-python-plugin cloudformation-cli-typescript-plugin

# Create module
## Create module template
[cloudshell-user@ip-10-2-84-35 s3-module]$ cfn init
Initializing new project
Do you want to develop a new resource(r) or a module(m) or a hook(h)?.
>> m
What's the name of your module type?
(<Organization>::<Service>::<Name>::MODULE)
>> MyCompany::S3::Bucket::MODULE
Directory  /home/cloudshell-user/s3-module/fragments  Created 
Initialized a new project in /home/cloudshell-user/s3-module

## Verify module template
[cloudshell-user@ip-10-2-84-35 s3-module]$ ls
fragments  rpdk.log
[cloudshell-user@ip-10-2-84-35 s3-module]$ ls fragments/
sample.json
[cloudshell-user@ip-10-2-84-35 s3-module]$ cat fragments/sample.json 
{
    "AWSTemplateFormatVersion": "2010-09-09",
    "Description": "A module example wrapping an S3 Bucket. The features are Versioning, Encryption and DeletionPolicy.",
    "Parameters": {
        "BucketName": {
            "Description": "Name for the bucket",
            "Type": "String"
        }
    },
    "Resources": {
        "S3Bucket": {
            "Type": "AWS::S3::Bucket",
            "DeletionPolicy": "Retain",
            "UpdateReplacePolicy": "Retain",
            "Properties": {
                "BucketName": {
                    "Ref": "BucketName"
                },
                "BucketEncryption": {
                    "ServerSideEncryptionConfiguration": [
                        {
                            "ServerSideEncryptionByDefault": {
                                "SSEAlgorithm": "AES256"
                            }
                        }
                    ]
                },
                "VersioningConfiguration": {
                    "Status": "Enabled"
                }
            }
        }
    }
}

## Remove fragment 
[cloudshell-user@ip-10-2-84-35 s3-module]$ cd fragments/
[cloudshell-user@ip-10-2-84-35 fragments]$ ls
sample.json
[cloudshell-user@ip-10-2-84-35 fragments]$ rm sample.json 

## Create new fragment with s3-bucket.yaml content
cat > s3-bucket.yaml

# Submit module
[cloudshell-user@ip-10-2-84-35 fragments]$ cd ..
[cloudshell-user@ip-10-2-84-35 s3-module]$ ls 
fragments  rpdk.log
[cloudshell-user@ip-10-2-84-35 s3-module]$ cfn submit -v
Validating your module fragments...
Run scan of template /home/cloudshell-user/s3-module/fragments/s3-bucket.yaml
Module fragment is valid.
Creating CloudFormationManagedUploadInfrastructure
CloudFormationManagedUploadInfrastructure stack was successfully created
Successfully submitted type. Waiting for registration with token '926e8248-07d5-4e02-91f7-e8a9a37dbddd' to complete.
Registration complete.
{'ProgressStatus': 'COMPLETE', 'Description': 'Deployment is currently in DEPLOY_STAGE of status COMPLETED', 'TypeArn': 'arn:aws:cloudformation:eu-west-3:612187453729:type/module/MyCompany-S3-Bucket-MODULE', 'TypeVersionArn': 'arn:aws:cloudformation:eu-west-3:612187453729:type/module/MyCompany-S3-Bucket-MODULE/00000001', 'ResponseMetadata': {'RequestId': '0392cfa5-52df-4155-b5c5-9a72bc6c213c', 'HTTPStatusCode': 200, 'HTTPHeaders': {'x-amzn-requestid': '0392cfa5-52df-4155-b5c5-9a72bc6c213c', 'date': 'Thu, 23 Nov 2023 17:58:11 GMT', 'content-type': 'text/xml', 'content-length': '685', 'connection': 'keep-alive'}, 'RetryAttempts': 0}}
[cloudshell-user@ip-10-2-84-35 s3-module]$ 

# Go to modules on Cloudformation registry