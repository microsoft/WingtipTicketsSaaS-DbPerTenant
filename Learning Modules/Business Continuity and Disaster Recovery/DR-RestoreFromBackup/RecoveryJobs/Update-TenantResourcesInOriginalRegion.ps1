<#
.SYNOPSIS
  Reconfigures servers and elastic pools in the Wingtip primary region to match settings in the recovery region 

.DESCRIPTION
  This script is intended to be run as a background job in the 'Repatriate-IntoPrimaryRegion' script that repatriates the Wingtip SaaS app environment (apps, databases, servers e.t.c) from a recovery region back into the primary region.
  The script update the configuration of elastic pools in the primary region and additionally creates any pools and servers provisioned in the recovery region that don't exist in the primary region. 

.PARAMETER WingtipRecoveryResourceGroup
  Resource group that will be used to contain recovered resources

.EXAMPLE
  [PS] C:\>.\Update-TenantResourcesInPrimaryRegion.ps1 -WingtipRecoveryResourceGroup <recovery region>
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
$tenantCatalog = Get-Catalog -ResourceGroupName $WingtipRecoveryResourceGroup -WtpUser $wtpUser.Name

# Find any previous tenant resource update operations to get most current state of recovered resources 
# This allows the script to be re-run if an error during deployment 
$deploymentName = "ReconfigureTenantResources"
$pastDeployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $wtpUser.ResourceGroupName -Name $deploymentName -ErrorAction SilentlyContinue 2>$null

# Wait for past deployment to complete if it's still active 
while (($pastDeployment) -and ($pastDeployment.ProvisioningState -NotIn "Succeeded", "Failed", "Canceled"))
{
    # Wait for no more than 5 minutes (300 secs) for previous deployment to complete
    if ($pastDeploymentWaitTime -lt 300)
    {
        Write-Output "Waiting for previous deployment to complete ..."
        Start-Sleep $sleepInterval
        $pastDeploymentWaitTime += $sleepInterval
        $pastDeployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $wtpUser.ResourceGroupName -Name $deploymentName -ErrorAction SilentlyContinue 2>$null    
    }
    else
    {
        Stop-AzureRmResourceGroupDeployment -ResourceGroupName $wtpUser.ResourceGroupName -Name $deploymentName -ErrorAction SilentlyContinue 1>$null 2>$null
        break
    }
}

# Get list of servers and elastic pools that were recovered into the recovery region
$recoveryRegionServers = Get-ExtendedServer -Catalog $tenantCatalog | Where-Object {($_.ServerName -Match "$($config.RecoveryRoleSuffix)$")}
$recoveryRegionElasticPools = Get-ExtendedElasticPool -Catalog $tenantCatalog | Where-Object {($_.ServerName -Match "$($config.RecoveryRoleSuffix)$")}

# Get list of servers that exist in original region 
$originRegionServers = (Find-AzureRmResource -ResourceGroupNameEquals $wtpUser.ResourceGroupName -ResourceType "Microsoft.sql/servers").Name

# Save server configuration settings
[array]$tenantServerConfigurations = @()
foreach($server in $recoveryRegionServers)
{
  $originServerName = ($server.ServerName -split $config.RecoveryRoleSuffix)[0] + $config.OriginRoleSuffix

  [array]$tenantServerConfigurations += @{
        ServerName = "$originServerName"
        AdminLogin = "$($config.TenantAdminUserName)"
        AdminPassword = "$($config.TenantAdminPassword)"           
  }
  
  $originServerState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startReplication" -ServerName $originServerName 
  $recoveryServerState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startReplication" -ServerName $server.ServerName
}

# Save elastic pool configuration settings. Pools are updated even though they may exist in the original region to sync any configuration changes that happened during recovery 
[array]$tenantElasticPoolConfigurations = @()
foreach($pool in $recoveryRegionElasticPools)
{
  $originServerName = ($server.ServerName -split $config.RecoveryRoleSuffix)[0] + $config.OriginRoleSuffix 

  [array]$tenantElasticPoolConfigurations += @{
      ServerName = "$originServerName"
      ElasticPoolName = "$($pool.ElasticPoolName)"
      Edition = "$($pool.Edition)"
      Dtu = "$($pool.Dtu)"
      DatabaseDtuMax = "$($pool.DatabaseDtuMax)"
      DatabaseDtuMin = "$($pool.DatabaseDtuMin)"
      StorageMB = "$($pool.StorageMB)"
    }
    # Update elastic pool recovery state 
    $originPoolState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startReplication" -ServerName $originServerName -ElasticPoolName $pool.ElasticPoolName
    $recoveryPoolState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startReplication" -ServerName $server.ServerName -ElasticPoolName $pool.ElasticPoolName
}
$tenantResourceCount = $tenantServerConfigurations.Count + $tenantElasticPoolConfigurations.Count

# Output recovery progress 
Write-Output "0% (0 of $tenantResourceCount)"

# Reconfigure servers and elastic pools in primary region to match settings in the recovery region 
$deployment = New-AzureRmResourceGroupDeployment `
                  -Name $deploymentName `
                  -ResourceGroupName $wtpUser.ResourceGroupName `
                  -TemplateFile ("$using:scriptPath\..\..\Common\RecoveryTemplates\" + $config.ReconfigureTenantResourcesTemplate) `
                  -ServerConfigurationSettings $tenantServerConfigurations `
                  -PoolConfigurationSettings $tenantElasticPoolConfigurations `
                  -ErrorAction Stop

# Mark server recovery as complete 
foreach($server in $tenantServerConfigurations)
{
  $recoveryServerName = ($server.ServerName -split $config.OriginRoleSuffix)[0] + $config.RecoveryRoleSuffix 

  $originServerState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startReplication" -ServerName $server.ServerName 
  $recoveryServerState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startReplication" -ServerName $recoveryServerName
}

# Mark pool recovery as complete 
foreach($pool in $tenantElasticPoolConfigurations)
{
  $recoveryServerName = ($server.ServerName -split $config.OriginRoleSuffix)[0] + $config.RecoveryRoleSuffix 

  $originPoolState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endReplication" -ServerName $server.ServerName -ElasticPoolName $pool.ElasticPoolName
  $recoveryPoolState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startReplication" -ServerName $recoveryServerName -ElasticPoolName $pool.ElasticPoolName
}

# Output recovery progress 
Write-Output "100% ($tenantResourceCount of $tenantResourceCount)"



