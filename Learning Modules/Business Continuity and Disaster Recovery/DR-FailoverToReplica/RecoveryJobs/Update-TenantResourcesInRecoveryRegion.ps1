<#
.SYNOPSIS
  Reconfigures servers and elastic pools in the Wingtip recovery region to match settings in the origin region 

.DESCRIPTION
  This script is intended to be run as a background job in the 'Failover-IntoRecoveryRegion' script that fails over tenant databases to the recovery region.
  The script reconfigures any existing tenant servers and elastic pools to match their counterparts in the origin region in preparation for a failover operation

.PARAMETER WingtipRecoveryResourceGroup
  Resource group containing Wingtip recovery resources

.EXAMPLE
  [PS] C:\>.\Update-TenantResourcesInRecoveryRegion.ps1 -WingtipRecoveryResourceGroup sampleRecoveryGroup
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

# Get the active tenant catalog in the recovery region
$tenantCatalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name

# Find any previous tenant resource update operations to get most current state of recovered resources 
# This allows the script to be re-run if an error during deployment 
$deploymentName = "ReconfigureTenantResources"
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

# Get list of servers and elastic pools in origin region
$originRegionServers = Get-ExtendedServer -Catalog $tenantCatalog | Where-Object {($_.ServerName -NotMatch "$($config.RecoveryRoleSuffix)$")}
$originRegionElasticPools = Get-ExtendedElasticPool -Catalog $tenantCatalog | Where-Object {($_.ServerName -NotMatch "$($config.RecoveryRoleSuffix)$")}

# Save server configuration settings
[array]$tenantServerConfigurations = @()
foreach($server in $originRegionServers)
{
  $recoveryServerName = $server.ServerName + $config.RecoveryRoleSuffix

  # Check if server exists in recovery region
  $recoveryServerExists = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceNameEquals $recoveryServerName -ResourceType "Microsoft.Sql/servers"

  if (!$recoveryServerExists)
  {
    [array]$tenantServerConfigurations += @{
        ServerName = "$recoveryServerName"
        AdminLogin = "$($config.TenantAdminUserName)"
        AdminPassword = "$($config.TenantAdminPassword)"           
    }  
  }  
}

# Save elastic pool configuration settings. 
[array]$tenantElasticPoolConfigurations = @()
foreach($pool in $originRegionElasticPools)
{
  $recoveryServerName = $pool.ServerName + $config.RecoveryRoleSuffix

  # Check if pool exists with correct configuration
  $recoveryPoolSynced = $false
  $recoveryPoolExists = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceNameEquals "$recoveryServerName/$($pool.ElasticPoolName)"
  
  if ($recoveryPoolExists)
  {
    $recoveryPool = Get-AzureRmSqlElasticPool -ResourceGroupName $WingtipRecoveryResourceGroup -ServerName $recoveryServerName
    if
    (
      $recoveryPool.Edition -eq $pool.Edition -and
      $recoveryPool.Dtu -ge $pool.Dtu -and 
      $recoveryPool.DatabaseDtuMax -ge $pool.DatabaseDtuMax -and
      $recoveryPool.DatabaseDtuMin -ge $pool.DatabaseDtuMin -and
      $recoveryPool.StorageMB -ge $pool.StorageMB       
    )
    {
      $recoveryPoolSynced = $true
    }
  }

  if (!$recoveryPoolSynced)
  {
    [array]$tenantElasticPoolConfigurations += @{
      ServerName = "$recoveryServerName"
      ElasticPoolName = "$($pool.ElasticPoolName)"
      Edition = "$($pool.Edition)"
      Dtu = "$($pool.Dtu)"
      DatabaseDtuMax = "$($pool.DatabaseDtuMax)"
      DatabaseDtuMin = "$($pool.DatabaseDtuMin)"
      StorageMB = "$($pool.StorageMB)"
    }

    $poolServerConfiguration = @{
      ServerName = "$recoveryServerName"
      AdminLogin = "$($config.TenantAdminUserName)"
      AdminPassword = "$($config.TenantAdminPassword)"     
    }

    if ($tenantServerConfigurations -notcontains $poolServerConfiguration)
    {
      $tenantServerConfigurations+= $poolServerConfiguration
    }    
  }  
}
$tenantResourceCount = $tenantServerConfigurations.Count + $tenantElasticPoolConfigurations.Count

if ($tenantResourceCount -eq 0)
{
  Write-Output "All resources synced"
  exit
}

# Output recovery progress
Write-Output "0% (0 of $tenantResourceCount)"

# Reconfigure servers and elastic pools in primary region to match settings in the recovery region 
$deployment = New-AzureRmResourceGroupDeployment `
                  -Name $deploymentName `
                  -ResourceGroupName $WingtipRecoveryResourceGroup `
                  -TemplateFile ("$using:scriptPath\RecoveryTemplates\" + $config.ReconfigureTenantResourcesTemplate) `
                  -ServerConfigurationSettings $tenantServerConfigurations `
                  -PoolConfigurationSettings $tenantElasticPoolConfigurations `
                  -ErrorAction Stop

# Output recovery progress 
Write-Output "100% ($tenantResourceCount of $tenantResourceCount)"

