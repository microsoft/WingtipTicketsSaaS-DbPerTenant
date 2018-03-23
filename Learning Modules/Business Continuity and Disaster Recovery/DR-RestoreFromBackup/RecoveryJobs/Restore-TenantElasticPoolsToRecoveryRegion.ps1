<#
.SYNOPSIS
  Restores tenant elastic pools in origin Wingtip region to recovery region

.DESCRIPTION
  This script is intended to be run as a background job in the 'Restore-IntoSecondaryRegion' script that recovers the Wingtip SaaS app environment (apps, databases, servers e.t.c) into a recovery region.
  The script creates tenant elastic pools that will be used to host tenant databases restored from the original Wingtip location. 

.PARAMETER WingtipRecoveryResourceGroup
  Resource group that will be used to contain recovered resources

.EXAMPLE
  [PS] C:\>.\Restore-TenantElasticPoolsToRecoveryRegion.ps1 -WingtipRecoveryResourceGrou "sampleResourceGroup"
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

# Get the recovery region resource group
$recoveryResourceGroup = Get-AzureRmResourceGroup -Name $WingtipRecoveryResourceGroup

# Get the tenant catalog in the recovery region
$tenantCatalog = Get-Catalog -ResourceGroupName $WingtipRecoveryResourceGroup -WtpUser $wtpUser.Name
while ($tenantCatalog.Database.ResourceGroupName -ne $WingtipRecoveryResourceGroup)
{
  $tenantCatalog = Get-Catalog -ResourceGroupName $WingtipRecoveryResourceGroup -WtpUser $wtpUser.Name
}

# Get list of tenant elastic pools to be recovered 
$tenantElasticPools = @()
$tenantElasticPools += Get-ExtendedElasticPool -Catalog $tenantCatalog | Where-Object {($_.ServerName -NotMatch "$($config.RecoveryRoleSuffix)$")}

$recoveredPoolCount = 0
$poolCount = $tenantElasticPools.length 
$sleepInterval = 10
$pastDeploymentWaitTime = 0
$deploymentName = "TenantElasticPoolRecovery"

# Find any previous elastic pool recovery operations to get most current state of recovered resources 
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

# Check for elastic pools that have previously been recovered 
$restoredElasticPools = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers/elasticpools"
foreach ($pool in $tenantElasticPools)
{
  $recoveredServerName = ($pool.ServerName) + $config.RecoveryRoleSuffi
  $compoundPoolName = "$($recoveredServerName)/$($pool.ElasticPoolName)"
  $pool | Add-Member "CompoundPoolName" $compoundPoolName

  if (($restoredElasticPools.Name -contains $pool.CompoundPoolName) -and ($pool.RecoveryState -In 'restoring', 'complete'))
  {
    $poolState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endRecovery" -ServerName $pool.ServerName -ElasticPoolName $pool.ElasticPoolName
    $recoveredPoolCount += 1
  }
  elseif ($pool.RecoveryState -In 'restored')
  {
    $recoveredPoolCount += 1
  }
}

# Output recovery progress 
$elasticPoolRecoveryPercentage = [math]::Round($recoveredPoolCount/$poolCount,2)
$elasticPoolRecoveryPercentage = $elasticPoolRecoveryPercentage * 100
Write-Output "$elasticPoolRecoveryPercentage% ($recoveredPoolCount of $poolCount)"

while ($recoveredPoolCount -lt $poolCount)
{
  $recoveredServerList = Get-ExtendedServer -Catalog $tenantCatalog | Where-Object {($_.ServerName -NotMatch "$($config.RecoveryRoleSuffix)$") -and ($_.RecoveryState -eq 'restored')}
  
  # Sleep and check back again later if no servers have been recovered 
  if (!$recoveredServerList)
  {
    Start-Sleep $sleepInterval
  }
  # Recover all elastic pools in restored tenant servers 
  else
  {
    $poolRecoveryQueue = @()
    [array]$elasticPoolConfigurations = @()

    # Generate list of pools that will be recovered in current loop iteration
    foreach($elasticPool in $tenantElasticPools)
    {
        # Add elastic pools that are eligible to be recovered to the pool queue 
        if (($recoveredServerList.ServerName -contains $elasticPool.ServerName) -and ($elasticPool.RecoveryState -In "n/a","restoring","complete"))
        {
          $poolRecoveryQueue += $elasticPool
          $recoveredServerName = ($elasticPool.ServerName) + $config.RecoveryRoleSuffix
          $recoveredServer = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceNameEquals $recoveredServerName
          [array]$elasticPoolConfigurations += @{
            ServerName = "$($recoveredServer.Name)"
            Location = "$($recoveredServer.Location)"
            ElasticPoolName = "$($elasticPool.ElasticPoolName)"
            Edition = "$($elasticPool.Edition)"
            Dtu = "$($elasticPool.Dtu)"
            DatabaseDtuMax = "$($elasticPool.DatabaseDtuMax)"
            DatabaseDtuMin = "$($elasticPool.DatabaseDtuMin)"
            StorageMB = "$($elasticPool.StorageMB)"
          }

          # Update elastic pool recovery state 
          $poolState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startRecovery" -ServerName $elasticPool.ServerName -ElasticPoolName $elasticPool.ElasticPoolName
        }
        elseif ($elasticPool.RecoveryState -NotIn "n/a","restoring","complete")
        {
          $poolState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endRecovery" -ServerName $elasticPool.ServerName -ElasticPoolName $elasticPool.ElasticPoolName
          $recoveredPoolCount += 1
        }        
    }

    # Output recovery progress 
    $elasticPoolRecoveryPercentage = [math]::Round($recoveredPoolCount/$poolCount,2)
    $elasticPoolRecoveryPercentage = $elasticPoolRecoveryPercentage * 100
    Write-Output "$elasticPoolRecoveryPercentage% ($recoveredPoolCount of $poolCount)"

    # Recover tenant elastic pools in queue 
    if ($poolRecoveryQueue.Count -gt 0)
    {
      $deployment = New-AzureRmResourceGroupDeployment `
                      -Name $deploymentName `
                      -ResourceGroupName $recoveryResourceGroup.ResourceGroupName `
                      -TemplateFile ("$using:scriptPath\RecoveryTemplates\" + $config.TenantElasticPoolRestoreBatchTemplate) `
                      -PoolConfigurationObjects $elasticPoolConfigurations `
                      -ErrorAction Stop

      # Mark elastic pools as recovered if no error has occurred
      foreach ($pool in $poolRecoveryQueue)
      {
        $poolState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endRecovery" -ServerName $pool.ServerName -ElasticPoolName $pool.ElasticPoolName 
      }
      $recoveredPoolCount += $poolRecoveryQueue.length
    } 

    # Output recovery progress 
    $elasticPoolRecoveryPercentage = [math]::Round($recoveredPoolCount/$poolCount,2)
    $elasticPoolRecoveryPercentage = $elasticPoolRecoveryPercentage * 100
    Write-Output "$elasticPoolRecoveryPercentage% ($recoveredPoolCount of $poolCount)"
  }    
}
