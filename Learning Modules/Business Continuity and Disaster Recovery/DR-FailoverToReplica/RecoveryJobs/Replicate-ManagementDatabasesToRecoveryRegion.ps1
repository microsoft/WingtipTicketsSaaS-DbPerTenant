<#
.SYNOPSIS
  Replicates management databases including the catalog database to recovery region

.DESCRIPTION
  This script is intended to be run as a background job in the DR scripts.
  The script replicates tenant databases by using SQL database geo-repliation

.PARAMETER WingtipRecoveryResourceGroup
  Resource group that will be used to contain recovered resources

.EXAMPLE
  [PS] C:\>.\Replicate-ManagementDatabasesToRecoveryRegion.ps1 -WingtipRecoveryResourceGroup "sampleRecoveryResourceGroup"
#>
[cmdletbinding()]
param (
    [parameter(Mandatory=$true)]
    [String] $WingtipRecoveryResourceGroup
)

Import-Module "$using:scriptPath\..\..\Common\CatalogAndDatabaseManagement" -Force
Import-Module "$using:scriptPath\..\..\WtpConfig" -Force
Import-Module "$using:scriptPath\..\..\UserConfig" -Force

# Stop execution on error 
$ErrorActionPreference = "Stop"
  
# Login to Azure subscription
$credentialLoad = Import-AzureRmContext -Path "$env:TEMP\profile.json"
if (!$credentialLoad)
{
    Initialize-Subscription
}

# Get deployment configuration  
$wtpUser = Get-UserConfig
$config = Get-Configuration
$currentSubscriptionId = Get-SubscriptionId

# Get the active tenant catalog 
$tenantCatalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name

# Get the recovery region resource group
$recoveryResourceGroup = Get-AzureRmResourceGroup -Name $WingtipRecoveryResourceGroup

$sleepInterval = 10
$pastDeploymentWaitTime = 0
$originCatalogServerName = $config.CatalogServerNameStem + $wtpUser.Name
$recoveryCatalogServerName = $config.CatalogServerNameStem + $wtpUser.Name + $config.RecoveryRoleSuffix

# Find any previous database recovery operations to get most current state of recovered resources 
# This allows the script to be re-run if an error during deployment 
$pastDeployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $WingtipRecoveryResourceGroup -Name "DeployCatalogFailoverGroup" -ErrorAction SilentlyContinue 2>$null

# Wait for past deployment to complete if it's still active 
while (($pastDeployment) -and ($pastDeployment.ProvisioningState -NotIn "Succeeded", "Failed", "Canceled"))
{
  # Wait for no more than 5 minutes (300 secs) for previous deployment to complete
  if ($pastDeploymentWaitTime -lt 300)
  {
    Write-Output "Waiting for previous deployment to complete ..."
    Start-Sleep $sleepInterval
    $pastDeploymentWaitTime += $sleepInterval
    $pastDeployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $WingtipRecoveryResourceGroup -Name "DeployCatalogFailoverGroup" -ErrorAction SilentlyContinue 2>$null    
  }
  else
  {
    Stop-AzureRmResourceGroupDeployment -ResourceGroupName $WingtipRecoveryResourceGroup -Name "DeployCatalogFailoverGroup" -ErrorAction SilentlyContinue 1>$null 2>$null
    break
  }    
}

# Wait until catalog recovery server has been created before starting catalog database replication
$recoveryCatalogServer = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers" -ResourceNameEquals $recoveryCatalogServerName
while (!$recoveryCatalogServer)
{
  Start-Sleep $sleepInterval
  $recoveryCatalogServer = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers" -ResourceNameEquals $recoveryCatalogServerName
}

$managementDatabaseCount = (Get-AzureRmSqlDatabase -ResourceGroupName $wtpUser.ResourceGroupName -ServerName $originCatalogServerName | Where-Object {$_.DatabaseName -ne 'master'}).Count
$catalogFailoverGroupName = $config.CatalogServerNameStem + "group-" + $wtpUser.Name

# Output recovery progress 
Write-Output "Replicating ... (0 of $managementDatabaseCount complete)"

# Deploy failover group for catalog server  
$deployment = New-AzureRmResourceGroupDeployment `
                -Name "DeployCatalogFailoverGroup" `
                -ResourceGroupName $wtpUser.ResourceGroupName `
                -TemplateFile ("$using:scriptPath\RecoveryTemplates\" + $config.FailoverGroupTemplate) `
                -OriginServerName $originCatalogServerName `
                -RecoveryServerName $recoveryCatalogServerName `
                -RecoveryResourceGroupName $WingtipRecoveryResourceGroup `
                -FailoverGroupName $catalogFailoverGroupName `
                -ErrorAction Stop

# Replicate all management databases in catalog server
$originServer = Get-AzureRmSqlServer -ResourceGroupName $wtpUser.ResourceGroupName -ServerName $originCatalogServerName
$catalogFailoverGroup = Get-AzureRmSqlDatabaseFailoverGroup -ResourceGroupName $wtpUser.ResourceGroupName -ServerName $originCatalogServerName -FailoverGroupName $catalogFailoverGroupName
$managementDatabases = Get-AzureRmSqlDatabase -ServerName $originCatalogServerName -ResourceGroupName $wtpUser.ResourceGroupName | Where-Object {$_.DatabaseName -ne 'master'}
$catalogFailoverGroup = $catalogFailoverGroup | Add-AzureRmSqlDatabaseToFailoverGroup -Database $managementDatabases

# Output recovery progress 
Write-Output "Replicated ($managementDatabaseCount of $managementDatabaseCount)"
