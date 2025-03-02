# Push files to S3 and create stack

[CmdletBinding()]
param (
    [String]
    $action = "update-stack",
    [String]
    $bucket = "hawkfund-cloudformation",
    [String]
    $bucketKey = "90_SiteToSiteVpn",
    [String]
    $templateName = "90_ROOT_SiteToSiteVpn.yaml",
    [String]
    $stackName = "ANS-90",
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

function PushToS3 {
    Write-Host "Push files modified the last $days days and $minutes minutes"
    $files = $(Get-ChildItem -Path .\*.yaml | Where-Object {$_.lastwritetime -gt (Get-Date).AddDays(-$days).AddMinutes(-$minutes)} | Select-Object Name)
    
    foreach ($f in $files) {
        $fileName =  $f.Name
        Write-Host "Push $ffileName to s3://$bucket/$bucketKey/$fileName"
        aws s3 cp $fileName s3://$bucket/$bucketKey/$fileName
    }
    return $true
}

function CreateStack {
    param (
        [String]
        $stackName,
        [String]
        $region = "eu-west-3"
        )
    Write-Host "Create stack $stackName in Region $region"
    aws cloudformation create-stack --stack-name $stackName --template-url $templateUrl --disable-rollback --region $region --capabilities $capabilities
    return $false
}

function UpdateStack {
    param (
        [String]
        $stackName,
        [String]
        $region = "eu-west-3"
        )
    Write-Host "Update stack $stackName in Region $region"
    aws cloudformation update-stack --stack-name $stackName --template-url $templateUrl --disable-rollback --region $region --capabilities $capabilities
    return $false
}

function DeleteRootStack {
    param (
        [String]
        $stackName,
        [String]
        $region = "eu-west-3"
        )
    Write-Host "Delete ROOT stack $stackName in Region $region"
    aws cloudformation delete-stack --stack-name $stackName --region $region
    return $false
}

function GetStackInformation {
    param (
        [String]
        $stackName,
        [String]
        $region = "eu-west-3"
        )
    Write-Host "Get Stacks with name that contain $stackName in Region $region"
    $query = "StackSummaries[?contains(StackName,'" + $stackName + "')]"
    $stacksJson = aws cloudformation list-stacks --query $query --output json --region $region
    # Convertir la sortie JSON en objet PowerShell
    $stacks = $stacksJson | ConvertFrom-Json

    # Extraire les informations pertinentes et les stocker dans un objet système
    $stackObjects = @()
    foreach ($stack in $stacks) {
        Write-Host $stack.StackName
        $stackObject = [PSCustomObject]@{
            CreationTime = $stack.CreationTime
            DeletionTime = $stack.DeletionTime
            LastUpdatedTime = $stack.LastUpdatedTime
            StackId      = $stack.StackId
            StackName    = $stack.StackName
            StackStatus  = $stack.StackStatus
            TemplateDescription =$stack.TemplateDescription
        }
        $stackObjects += $stackObject
    }
    return $stackObjects
    
}

function DeleteAllStacks {
    param (
        [String]
        $stackName,
        [String]
        $region = "eu-west-3"
        )
    Write-Host "Delete All Stacks"    
    $stackObjects = GetStackInformation -stackName $stackName -region $region
    ForEach ($stack in $stackObjects) {
        <# $stack is the current item #>
        switch -WildCard ($stack.StackStatus) {
            
            "*_IN_PROGRESS" {
                Write-Host "Nothing to do for $stack.StackName IN_PROGRESS"; Break
              }
            "DELETE_COMPLETE" {
                Write-Host "Nothing to do for $stack.StackName DELETED"; Break
            }
            "DELETE_FAILED" {
                Write-Host "Force deleting $stack.StackName"
                aws cloudformation delete-stack --stack-name $stack.StackName --region $region --deletion-mode FORCE_DELETE_STACK
                Break
            }
            Default {
                Write-Host "Deleting $stack.StackName"
                aws cloudformation delete-stack --stack-name $stack.StackName --region $region
            }
        }
        Write-Host $stack.StackName
    }
    return $false
}

while ($continue){
    write-host “---------------------- Action on stack -----------------------”
    write-host "1. Push to S3"
    write-host “2. Create Stack”
    write-host "3. Update Stack"
    write-host "4. Delete ROOT Stack"
    write-host "5. Delete Stacks"
    write-host "Default exit"
    write-host "--------------------------------------------------------------"
    $choix = read-host “Choose an action”
    switch ($choix){
      1 {
          # Push files to S3
          $continue = PushToS3
      }
      2 {
          # Create stacks
          $continue = CreateStack -stackName $stackName -region $region
      }
      3 {
          # Update stacks
          $continue = UpdateStack -stackName $stackName -region $region
      }
      4 {
          # Delete ROOT stacks
          $continue = DeleteRootStack -stackName $stackName -region $region
      }
      5 {
          # Delete all stacks
          $continue = DeleteAllStacks -stackName $stackName -region $region
      }
      Default {
          $continue = $false
      }
    }
}
