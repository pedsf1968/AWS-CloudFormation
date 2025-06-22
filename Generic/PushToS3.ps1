# Copy files so S3

[CmdletBinding()]
param (
    [String]
    $bucket = "hawkfund-cloudformation",
    [String]
    $bucketKey = "Generic",
    [String]
    $days = 0,
    [String]
    $minutes = 15
)

$resources = @(
    "EC2"
    "ElasticLoadBalancingV2"
    "IAM"
    "Lambda"
    "Route53"
    "SQS"
    "SSM"
    "VPC"
)

Write-Host "Push files modified the last $days days and $minutes minutes"

foreach ($resource in $resources) {
    #$files = $(Get-ChildItem -Path $resource\*.yaml |where {$_.lastwritetime -gt (get-date).adddays(-$days)} | Select-Object Name)
    $files = $(Get-ChildItem -Path $resource\*.yaml | Where {$_.lastwritetime -gt (Get-Date).AddDays(-$days).AddMinutes(-$minutes)} | Select-Object Name)
    Write-Host "Resource: $resource"

    foreach ($f in $files) {
        $fileName =  $f.Name
        aws s3 cp $resource/$fileName s3://$bucket/$bucketKey/$resource/$fileName
    }
}

