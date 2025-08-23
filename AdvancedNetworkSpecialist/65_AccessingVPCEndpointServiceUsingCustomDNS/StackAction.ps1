#Requires -Modules @{ ModuleName="AWS.Tools.CloudFormation"; ModuleVersion="4.0" }

<#
.SYNOPSIS
    Manages CloudFormation stacks with S3 template storage
.DESCRIPTION
    Uploads CloudFormation templates to S3 and manages stack lifecycle (create/update/delete)
.PARAMETER Action
    Default action to perform (create-stack, update-stack, delete-stack, push-files)
.PARAMETER Bucket
    S3 bucket name for template storage
.PARAMETER BucketKey
    S3 key prefix (defaults to current directory name)
.PARAMETER TemplateName
    CloudFormation template filename (auto-detected if contains ROOT)
.PARAMETER StackName
    CloudFormation stack name (auto-generated if not provided)
.PARAMETER Region
    AWS region for CloudFormation operations
.PARAMETER Capabilities
    CloudFormation capabilities required
.PARAMETER Days
    Filter files modified within X days
.PARAMETER Minutes
    Filter files modified within X minutes
.PARAMETER ParameterFile
    Path to parameters file (JSON format)
.PARAMETER DryRun
    Show what would be done without executing
.EXAMPLE
    .\StackAction.ps1 -Action "create-stack" -StackName "my-stack"
.EXAMPLE
    .\StackAction.ps1 -DryRun -TemplateName "root-template.yaml"

    .\StackAction.ps1 -Action "delete-stack" -StackName "my-stack"

    .\StackAction.ps1 -Action "interactive"
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [ValidateSet("create-stack", "update-stack", "delete-stack", "push-files", "interactive")]
    [String]$Action = "interactive",
    
    [ValidateNotNullOrEmpty()]
    [String]$Bucket = "hawkfund-cloudformation",
    
    [String]$BucketKey,
    [String]$TemplateName,
    [String]$StackName,
    
    [ValidateSet("us-east-1", "us-west-2", "eu-west-1", "eu-west-3", "ap-southeast-1")]
    [String]$Region = "eu-west-3",
    
    [ValidateSet("CAPABILITY_IAM", "CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND")]
    [String]$Capabilities = "CAPABILITY_NAMED_IAM",
    
    [ValidateRange(0, 365)]
    [Int]$Days = 0,
    
    [ValidateRange(0, 1440)]
    [Int]$Minutes = 15,
    
    [String]$ParameterFile,
    
    [Switch]$DryRun
)

# Initialize logging
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Log {
    param([String]$Message, [String]$Level = "Info")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "Error" { "Red" }
        "Warning" { "Yellow" }
        "Success" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] $Message" -ForegroundColor $color
}

function Test-AWSConfiguration {
    try {
        $null = Get-AWSCredential -ProfileName default -ErrorAction Stop
        return $true
    }
    catch {
        Write-Log "AWS credentials not configured. Please run 'aws configure' first." -Level "Error"
        return $false
    }
}

function Get-DefaultValues {
    # Get bucket key from current directory
    if (-not $script:BucketKey) {
        $script:BucketKey = Split-Path (Get-Location) -Leaf
        $script:Key = ($currentDir -split '_')
        Write-Log "Using bucket key: $script:BucketKey"
    }

    # Find template file containing ROOT
    if (-not $script:TemplateName) {
        $rootFiles = Get-ChildItem -Name "*ROOT*.yaml", "*ROOT*.yml" -ErrorAction SilentlyContinue
        if ($rootFiles.Count -eq 1) {
            $script:TemplateName = $rootFiles
            Write-Log "Found template: $script:TemplateName"
        }
        elseif ($rootFiles.Count -gt 1) {
            Write-Log "Multiple ROOT templates found. Please specify -TemplateName parameter." -Level "Warning"
            $rootFiles | ForEach-Object { Write-Host "  - $_" }
            return $false
        }
        else {
            Write-Log "No ROOT template found. Please specify -TemplateName parameter." -Level "Error"
            return $false
        }
    }

    # Generate stack name
    if (-not $script:StackName) {
        $currentDir = Split-Path (Get-Location) -Leaf
        $prefix = ($currentDir -split '_')[0]
        $script:StackName = "ANS-$prefix"
        Write-Log "Using stack name: $script:StackName"
    }

    return $true
}

function Get-FilesToUpload {
    param([String]$FilterType = "all")
    
    $wildcards = @(".yaml",".yml")
    
    switch ($FilterType) {
        "all" {
            Write-Host "Push all files to S3 Bucket"
            $files = Get-ChildItem -Path . -Filter $baseFilter -File
        }
        "recent" {
            Write-Host "Push files modify during last $Days days and $Minutes minutes to S3 Bucket"
            $cutoffDate = (Get-Date).AddDays(-$Days).AddMinutes(-$Minutes)
            $files = Get-ChildItem -Path . -File | 
                Where-Object {$_.extension -in $wildcards} |
                Where-Object { $_.LastWriteTime -gt $cutoffDate }
        }
        default {
            throw "Invalid filter type: $FilterType"
        }
    }
    
    return $files
}

function Push-FilesToS3 {
    param([String]$FilterType = "all")
    
    try {
        $files = Get-FilesToUpload -FilterType $FilterType
        
        if ($files.Count -eq 0) {
            Write-Log "No files found to upload." -Level "Warning"
            return $false
        }

        Write-Log "Found $($files.Count) file(s) to upload:"
        $files | ForEach-Object { Write-Host "  - $($_.Name)" }

        if ($DryRun) {
            Write-Log "DRY RUN: Would upload files to s3://$Bucket/$BucketKey/" -Level "Warning"
            return $true
        }

        $successCount = 0
        foreach ($file in $files) {
            $s3Key = "$BucketKey/$($file.Name)"
            try {
                Write-Log "Uploading $($file.Name) to s3://$Bucket/$s3Key"
                aws s3 cp $file.FullName "s3://$Bucket/$s3Key" --quiet
                if ($LASTEXITCODE -eq 0) {
                    $successCount++
                }
                else {
                    Write-Log "Failed to upload $($file.Name)" -Level "Error"
                }
            }
            catch {
                Write-Log "Error uploading $($file.Name): $($_.Exception.Message)" -Level "Error"
            }
        }

        Write-Log "Successfully uploaded $successCount of $($files.Count) files" -Level "Success"
        return $successCount -eq $files.Count
    }
    catch {
        Write-Log "Error in Push-FilesToS3: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}

function Test-StackExists {
    param([String]$StackName)
    
    try {
        $result = aws cloudformation describe-stacks --stack-name $StackName --region $Region 2>$null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}
function Wait-StackDeletion {
    param(
        [String]$StackName,
        [String]$Region,
        [Int]$TimeoutMinutes = 30,
        [Int]$CheckIntervalSeconds = 30
    )
    
    Write-Log "Monitoring stack deletion: $StackName" -Level "Info"
    $timeoutTime = (Get-Date).AddMinutes($TimeoutMinutes)
    $lastStatus = ""
    
    while ((Get-Date) -lt $timeoutTime) {
        try {
            # Vérifier le statut de la stack
            $stackInfo = aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].{Status:StackStatus,Reason:StackStatusReason}' --output json 2>$null
            
            if ($LASTEXITCODE -ne 0) {
                # La stack n'existe plus (erreur car elle est supprimée)
                Write-Log "Stack '$StackName' successfully deleted!" -Level "Success"
                return $true
            }
            
            $status = ($stackInfo | ConvertFrom-Json).Status
            
            # Afficher le statut seulement s'il a changé
            if ($status -ne $lastStatus) {
                Write-Log "Stack status: $status" -Level "Info"
                $lastStatus = $status
            }
            
            # Vérifier les statuts finaux
            switch ($status) {
                "DELETE_COMPLETE" {
                    Write-Log "Stack '$StackName' deleted successfully!" -Level "Success"
                    return $true
                }
                "DELETE_FAILED" {
                    $reason = ($stackInfo | ConvertFrom-Json).Reason
                    Write-Log "Stack deletion failed: $reason" -Level "Error"
                    return $false
                }
                "DELETE_IN_PROGRESS" {
                    Write-Host "." -NoNewline -ForegroundColor Yellow
                }
                default {
                    Write-Log "Unexpected status during deletion: $status" -Level "Warning"
                }
            }
            
            Start-Sleep -Seconds $CheckIntervalSeconds
        }
        catch {
            Write-Log "Error checking stack status: $($_.Exception.Message)" -Level "Error"
            Start-Sleep -Seconds $CheckIntervalSeconds
        }
    }
    
    Write-Log "Timeout reached ($TimeoutMinutes minutes). Stack deletion may still be in progress." -Level "Warning"
    return $false
}

function Invoke-StackOperation {
    param([String]$Operation)
    
    $templateUrl = "https://$Bucket.s3.$Region.amazonaws.com/$BucketKey/$TemplateName"
    
    if ($DryRun) {
        Write-Log "DRY RUN: Would $Operation stack '$StackName' using template: $templateUrl" -Level "Warning"
        return $true
    }

    $commonParams = @(
        "--stack-name", $StackName,
        "--region", $Region
    )

    if ($Operation -ne "delete") {
        $commonParams += @("--template-url", $templateUrl, "--capabilities", $Capabilities)
        
        # Add parameters file if specified
        if ($ParameterFile -and (Test-Path $ParameterFile)) {
            $commonParams += @("--parameters", "file://$ParameterFile")
        }
    }

    try {
        switch ($Operation) {
            "create" {
                Write-Log "Creating stack: $StackName"
                aws cloudformation create-stack @commonParams --enable-termination-protection --disable-rollback
            }
            "update" {
                Write-Log "Updating stack: $StackName"
                aws cloudformation update-stack @commonParams --disable-rollback
            }
            "delete" {
                Write-Log "Deleting stack: $StackName"
                # Remove termination protection first
                Write-Log "Removing termination protection..."
                aws cloudformation update-termination-protection --stack-name $StackName --no-enable-termination-protection --region $Region 2>$null
                
                # Initiate deletion
                aws cloudformation delete-stack --stack-name $StackName --region $Region
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Stack deletion initiated successfully" -Level "Success"
                    
                    # Demander si l'utilisateur veut surveiller la suppression
                    if ($Action -eq "interactive") {
                        $monitor = Read-Host "Do you want to monitor the deletion progress? (y/n)"
                        if ($monitor.ToLower() -in @("y", "yes", "o", "oui")) {
                            return Wait-StackDeletion -StackName $StackName -Region $Region
                        }
                    } else {
                        # En mode non-interactif, surveiller automatiquement
                        return Wait-StackDeletion -StackName $StackName -Region $Region
                    }
                    return $true
                } else {
                    Write-Log "Failed to initiate stack deletion" -Level "Error"
                    return $false
                }
            }
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Log "Stack operation '$Operation' initiated successfully" -Level "Success"
            if ($Operation -ne "delete") {
                Write-Log "Monitor progress at: https://console.aws.amazon.com/cloudformation/home?region=$Region#/stacks"
            }
            return $true
        }
        else {
            Write-Log "Stack operation failed with exit code: $LASTEXITCODE" -Level "Error"
            return $false
        }
    }
    catch {
        Write-Log "Error during stack operation: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}

# Fonction utilitaire pour supprimer plusieurs stacks avec surveillance
function Remove-MultipleStacks {
    param(
        [String[]]$StackNames,
        [String]$Region,
        [Int]$TimeoutMinutes = 30
    )
    
    Write-Log "Starting deletion of $($StackNames.Count) stacks" -Level "Info"
    
    # Initier la suppression de toutes les stacks
    $deletionJobs = @()
    foreach ($stackName in $StackNames) {
        if (Test-StackExists -StackName $stackName) {
            Write-Log "Initiating deletion of stack: $stackName"
            
            # Supprimer la protection contre la terminaison
            aws cloudformation update-termination-protection --stack-name $stackName --no-enable-termination-protection --region $Region 2>$null
            
            # Lancer la suppression
            aws cloudformation delete-stack --stack-name $stackName --region $Region
            
            if ($LASTEXITCODE -eq 0) {
                $deletionJobs += $stackName
                Write-Log "Deletion initiated for: $stackName" -Level "Success"
            } else {
                Write-Log "Failed to initiate deletion for: $stackName" -Level "Error"
            }
        } else {
            Write-Log "Stack '$stackName' does not exist" -Level "Warning"
        }
    }
    
    if ($deletionJobs.Count -eq 0) {
        Write-Log "No stacks to delete" -Level "Warning"
        return $true
    }
    
    # Surveiller la suppression de toutes les stacks
    Write-Log "Monitoring deletion of $($deletionJobs.Count) stacks..." -Level "Info"
    $timeoutTime = (Get-Date).AddMinutes($TimeoutMinutes)
    $completedStacks = @()
    
    while ($deletionJobs.Count -gt $completedStacks.Count -and (Get-Date) -lt $timeoutTime) {
        foreach ($stackName in $deletionJobs) {
            if ($stackName -in $completedStacks) {
                continue
            }
            
            try {
                $stackInfo = aws cloudformation describe-stacks --stack-name $stackName --region $Region --query 'Stacks[0].StackStatus' --output text 2>$null
                
                if ($LASTEXITCODE -ne 0) {
                    # Stack supprimée avec succès
                    Write-Log "✓ Stack '$stackName' deleted successfully" -Level "Success"
                    $completedStacks += $stackName
                } elseif ($stackInfo -eq "DELETE_FAILED") {
                    Write-Log "✗ Stack '$stackName' deletion failed" -Level "Error"
                    $completedStacks += $stackName
                } elseif ($stackInfo -eq "DELETE_IN_PROGRESS") {
                    Write-Host "." -NoNewline -ForegroundColor Yellow
                }
            }
            catch {
                # En cas d'erreur, considérer que la stack est supprimée
                Write-Log "✓ Stack '$stackName' appears to be deleted" -Level "Success"
                $completedStacks += $stackName
            }
        }
        
        if ($deletionJobs.Count -gt $completedStacks.Count) {
            Start-Sleep -Seconds 15
        }
    }
    
    Write-Host "" # Nouvelle ligne après les points
    
    $successCount = $completedStacks.Count
    $totalCount = $deletionJobs.Count
    
    Write-Log "Deletion summary: $successCount/$totalCount stacks processed" -Level "Info"
    
    if ($successCount -eq $totalCount) {
        Write-Log "All stacks deleted successfully!" -Level "Success"
        return $true
    } else {
        Write-Log "Some stacks may still be deleting or failed to delete" -Level "Warning"
        return $false
    }
}

function Show-InteractiveMenu {
    $continue = $true
    
    while ($continue) {
        Write-Host "`n" + "="*60
        Write-Host "CloudFormation Stack Management" -ForegroundColor Cyan
        Write-Host "="*60
        Write-Host "Current Configuration:" -ForegroundColor Yellow
        Write-Host "  Bucket: $Bucket"
        Write-Host "  Key: $BucketKey"
        Write-Host "  Template: $TemplateName"
        Write-Host "  Stack: $StackName"
        Write-Host "  Region: $Region"
        Write-Host ""
        Write-Host "Available Actions:" -ForegroundColor Green
        Write-Host "  0. Push all YAML files to S3"
        Write-Host "  1. Push recent files (last $Days day(s) and $Minutes minute(s)) to S3"
        Write-Host "  2. Create stack"
        Write-Host "  3. Update stack"
        Write-Host "  4. Delete stack"
        Write-Host "  5. Check stack status"
        Write-Host "  q. Quit"
        Write-Host "="*60

        $choice = Read-Host "Choose an action"
        
        switch ($choice.ToLower()) {
            "0" {
                Push-FilesToS3 -FilterType "all"
            }
            "1" {
                Push-FilesToS3 -FilterType "recent"
            }
            "2" {
                if (Test-StackExists -StackName $StackName) {
                    Write-Log "Stack '$StackName' already exists. Use update instead." -Level "Warning"
                }
                else {
                    Invoke-StackOperation -Operation "create"
                    $continue = $false
                }
            }
            "3" {
                if (Test-StackExists -StackName $StackName) {
                    Invoke-StackOperation -Operation "update"
                    $continue = $false
                }
                else {
                    Write-Log "Stack '$StackName' does not exist. Use create instead." -Level "Warning"
                }
            }
            "4" {
                $confirm = Read-Host "Are you sure you want to delete stack '$StackName'? (yes/no)"
                if ($confirm.ToLower() -eq "yes") {
                    Invoke-StackOperation -Operation "delete"
                    $continue = $false
                }
            }
            "5" {
                if (Test-StackExists -StackName $StackName) {
                    aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].{Name:StackName,Status:StackStatus,Created:CreationTime}' --output table
                }
                else {
                    Write-Log "Stack '$StackName' does not exist." -Level "Warning"
                }
            }
            { $_ -in @("q", "quit", "exit") } {
                $continue = $false
            }
            default {
                Write-Log "Invalid choice. Please try again." -Level "Warning"
            }
        }
        
        if ($continue) {
            Read-Host "`nPress Enter to continue..."
        }
    }
}

# Main execution
try {
    Write-Log "Starting CloudFormation Stack Management Script"
    
    # Validate AWS configuration
    if (-not (Test-AWSConfiguration)) {
        exit 1
    }
    
    # Set default values
    if (-not (Get-DefaultValues)) {
        exit 1
    }
    
    # Execute based on action
    switch ($Action.ToLower()) {
        "create-stack" {
            if (Test-StackExists -StackName $StackName) {
                Write-Log "Stack '$StackName' already exists." -Level "Error"
                exit 1
            }
            Invoke-StackOperation -Operation "create"
        }
        "update-stack" {
            if (-not (Test-StackExists -StackName $StackName)) {
                Write-Log "Stack '$StackName' does not exist." -Level "Error"
                exit 1
            }
            Invoke-StackOperation -Operation "update"
        }
        "delete-stack" {
            if (-not (Test-StackExists -StackName $StackName)) {
                Write-Log "Stack '$StackName' does not exist." -Level "Error"
                exit 1
            }
            Invoke-StackOperation -Operation "delete"
        }
        "push-files" {
            Push-FilesToS3 -FilterType "all"
        }
        "interactive" {
            Show-InteractiveMenu
        }
    }
    
    Write-Log "Script completed successfully" -Level "Success"
}
catch {
    Write-Log "Script failed: $($_.Exception.Message)" -Level "Error"
    exit 1
}
finally {
    $ProgressPreference = "Continue"
}