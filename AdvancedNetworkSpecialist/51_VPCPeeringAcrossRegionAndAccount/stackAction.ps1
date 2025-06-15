# Push files to S3 and create stack

[CmdletBinding()]
param (
    [String]
    $action = "update-stack",
    [String]
    $bucket = "hawkfund-cloudformation",
    [String]
    $bucketKey = "51_VPCPeeringAcrossRegionAndAccount",
    [String]
    $templateName = "51_ROOT_VPCPeeringAcrossRegionAndAccount.yaml",
    [String]
    $stackName = "ANS-51",
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
while ($continue){
    write-host “---------------------- Action on stack -----------------------”
    write-host "0. Push all files to S3"
    write-host "1. Push the last modified files from $days day(s) ans $minutes minute(s) to S3"
    write-host “2. Create”
    write-host "3. Update"
    write-host "4. Delete"
    write-host "Default exit"
    write-host "--------------------------------------------------------------"
    $choix = read-host “Choose an action”
    switch ($choix){
      0 {
          # Push files to S3
          Write-Host "Push all files"
          $files = $(Get-ChildItem -Path .\*.yaml| Select-Object Name)
          
          foreach ($f in $files) {
              $fileName =  $f.Name
              aws s3 cp $fileName s3://$bucket/$bucketKey/$fileName
          }
      }
      1 {
        # Push files to S3
        Write-Host "Push files modified the last $days days and $minutes minutes"
        $files = $(Get-ChildItem -Path .\*.yaml | Where-Object {$_.lastwritetime -gt (Get-Date).AddDays(-$days).AddMinutes(-$minutes)} | Select-Object Name)
        
        foreach ($f in $files) {
            $fileName =  $f.Name
            aws s3 cp $fileName s3://$bucket/$bucketKey/$fileName
        }
    }
    2 {
        # Create stacks
        Write-Host "Create stack $stackName"
        aws cloudformation create-stack --stack-name $stackName --template-url $templateUrl --disable-rollback --region $region --capabilities $capabilities
        $continue = $false
    }
    3 {
        # Update stacks
        Write-Host "Update stack $stackName"
        aws cloudformation update-stack --stack-name $stackName --template-url $templateUrl --disable-rollback --region $region --capabilities $capabilities
        $continue = $false
    }
    4 {
        # Delete stacks
        Write-Host "Delete stack $stackName"
        aws cloudformation delete-stack --stack-name $stackName --region $region
        $continue = $false
    }
    Default {
        $continue = $false
    }
  }
}