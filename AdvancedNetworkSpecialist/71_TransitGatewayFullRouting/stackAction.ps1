# Push files to S3 and create stack

[CmdletBinding()]
param (
    [String]
    $action = "update-stack",
    [String]
    $bucket = "hawkfund-cloudformation",
    [String]
    $bucketKey = "71_TransitGatewayFullRouting",
    [String]
    $templateName = "71_ROOT_TransitGatewayFullRouting.yaml",
    [String]
    $stackName = "ANS-71",
    [String]
    $region = "eu-west-3",
    [String]
    $capabilities = "CAPABILITY_NAMED_IAM",
    [String]
    $days = 0,
    [String]
    $minutes = 15
)

$templateUrl = "https://hawkfund-cloudformation.s3.eu-west-3.amazonaws.com/$bucketKey/$templateName"
$continue = $true

