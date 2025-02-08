# Copy files so S3

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
    $capabilities = "CAPABILITY_NAMED_IAM"
)

$templateUrl = "https://hawkfund-cloudformation.s3.eu-west-3.amazonaws.com/$bucketKey/$templateName"

$continue = $true
while ($continue){
  write-host “---------------------- Action on stack -----------------------”
  write-host “1. Create”
  write-host "2. Update"
  write-host "3. Delete"
  write-host "Default exit"
  write-host "--------------------------------------------------------------"
  $choix = read-host “Choose an action”
  switch ($choix){
    1 {
        Write-Host "Create stack $stackName"
        aws cloudformation create-stack --stack-name $stackName --template-url $templateUrl --disable-rollback --region $region --capabilities $capabilities
        $continue = $false
    }
    2 {
        Write-Host "Update stack $stackName"
        aws cloudformation update-stack --stack-name $stackName --template-url $templateUrl --disable-rollback --region $region --capabilities $capabilities
        $continue = $false
    }
    3 {
        Write-Host "Delete stack $stackName"
        aws cloudformation delete-stack --stack-name $stackName --region $region
        $continue = $false
    }
    Default {
        $continue = $false
    }
  }
}



