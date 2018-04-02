<#
.SYNOPSIS
  Replicates tenant servers and management servers into recovery region

.DESCRIPTION
  This script is intended to be run as a background job in DR scripts.
  The script creates replica tenant servers and management servers in a recovery region. These servers will serve as hot standbys that can be failed over to in the event of a disaster.

.PARAMETER WingtipRecoveryResourceGroup
  Resource group that will be used to contain recovered resources

.EXAMPLE
  [PS] C:\>.\Replicate-ServersToRecoveryRegion.ps1 -WingtipRecoveryResourceGroup "sampleRecoveryResourceGroup"
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

# Get the active tenant catalog 
$tenantCatalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name

# Get the recovery region resource group
$recoveryResourceGroup = Get-AzureRmResourceGroup -Name $WingtipRecoveryResourceGroup

$serverQueue = @()
[array]$serverConfigurations = @()
$replicatedServers = 0
$sleepInterval = 10
$pastDeploymentWaitTime = 0
$deploymentName = "WingtipSaaSServerReplication"

# Find any previous server recovery operations to get most current state of recovered resources 
# This allows the script to be re-run if an error during deployment 
$pastDeployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $WingtipRecoveryResourceGroup -Name $deploymentName -ErrorAction SilentlyContinue 2>$null

# Wait for past deployment to complete if it's still active 
while (($pastDeployment) -and ($pastDeployment.ProvisioningState -NotIn "Succeeded", "Failed", "Canceled"))
{
  # Wait for no more than 5 minutes (300 secs) for previous deployment to complete
  if ($pastDeploymentWaitTime -lt 300)
  {
      Write-Output "Waiting for previous deployment to complete ..."
      Start-Sleep $sleepInterval
      $pastDeploymentWaitTime += $sleepInterval
      $pastDeployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $WingtipRecoveryResourceGroup -Name $deploymentName -ErrorAction SilentlyContinue 2>$null    
  }
  else
  {
      Stop-AzureRmResourceGroupDeployment -ResourceGroupName $WingtipRecoveryResourceGroup -Name $deploymentName -ErrorAction SilentlyContinue 1>$null 2>$null
      break
  }  
}

# Get list of servers to be replicated
$serverList = @()
$serverList += Get-ExtendedServer -Catalog $tenantCatalog | Where-Object {($_.ServerName -NotMatch "$($config.RecoveryRoleSuffix)$")}
$catalogServer = New-Object -TypeName PsObject -Property @{ServerName = $config.CatalogServerNameStem + $wtpUser.Name; RecoveryState = 'n/a'; State = 'created'}
$serverList += $catalogServer
$restoredServers = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers"

foreach ($server in $serverList)
{
  # Only replicate servers that haven't already been replicated
  $serverRecoveryName = $server.ServerName + $config.RecoveryRoleSuffix
  if ($restoredServers.Name -notcontains $serverRecoveryName)
  {
    $serverQueue += $serverRecoveryName
    if ($server.ServerName -match $config.CatalogServerNameStem)
    {
      $adminLogin = $config.CatalogAdminUserName
      $adminPassword = $config.CatalogAdminPassword
    }
    else
    {
      $adminLogin = $config.TenantAdminUserName
      $adminPassword = $config.TenantAdminPassword
    }

    [array]$serverConfigurations += @{
      ServerName = "$serverRecoveryName"
      Location = "$($recoveryResourceGroup.Location)"
      AdminLogin = "$adminLogin"
      AdminPassword = "$adminPassword"
    }        
  }
  else
  {
    $replicatedServers += 1
  }  
}
  
# Output recovery progress 
$serverRecoveryPercentage = [math]::Round($replicatedServers/$serverList.length,2)
$serverRecoveryPercentage = $serverRecoveryPercentage * 100
Write-Output "Deploying ... ($($replicatedServers) of $($serverList.length) complete)"


# Replicate tenant servers and firewall rules in them 
# Note: In a production scenario you would additionally restore logins and users that existed in the primary server (see: https://docs.microsoft.com/en-us/azure/sql-database/sql-database-disaster-recovery)
if ($serverQueue.Count -gt 0)
{
  $deployment = New-AzureRmResourceGroupDeployment `
                  -Name $deploymentName `
                  -ResourceGroupName $recoveryResourceGroup.ResourceGroupName `
                  -TemplateFile ("$using:scriptPath\RecoveryTemplates\" + $config.TenantServerRestoreBatchTemplate) `
                  -ServerConfigurationObjects $serverConfigurations `
                  -ErrorAction Stop

  $replicatedServers += $serverQueue.Length
}

# Output recovery progress 
$serverRecoveryPercentage = [math]::Round($replicatedServers/$serverList.length,2)
$serverRecoveryPercentage = $serverRecoveryPercentage * 100
Write-Output "Deployed ($($replicatedServers) of $($serverList.length))"
