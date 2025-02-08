# Copy files so S3

[CmdletBinding()]
param (
    [String]
    $bucket = "hawkfund-cloudformation",
    [String]
    $bucketKey = "70_TransitGateway",
    [String]
    $days = 1
)


  
$files = $(Get-ChildItem -Path .\*.yaml |where {$_.lastwritetime -gt (get-date).adddays(-$days)} | Select-Object Name)

foreach ($f in $files) {
    $fileName =  $f.Name
    aws s3 cp $fileName s3://$bucket/$bucketKey/$fileName
}
