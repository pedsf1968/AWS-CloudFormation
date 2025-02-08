# Copy files so S3

[CmdletBinding()]
param (
    [String]
    $bucket = "hawkfund-cloudformation",
    [String]
    $bucketKey = "Generic",
    [String]
    $days = 1
)

$resources = @(
    "EC2"
    "IAM"
    "Lambda"
    "VPC"
)

foreach ($resource in $resources) {
    $files = $(Get-ChildItem -Path $resource\*.yaml |where {$_.lastwritetime -gt (get-date).adddays(-$days)} | Select-Object Name)

    foreach ($f in $files) {
        $fileName =  $f.Name
        aws s3 cp $resource/$fileName s3://$bucket/$bucketKey/$resource/$fileName
    }
}

