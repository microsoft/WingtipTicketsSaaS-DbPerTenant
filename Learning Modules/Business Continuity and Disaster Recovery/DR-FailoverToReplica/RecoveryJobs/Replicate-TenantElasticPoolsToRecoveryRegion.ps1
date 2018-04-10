<#
.SYNOPSIS
  Replicate tenant elastic pools to recovery region

.DESCRIPTION
  This script is intended to be run as a background job in the DR scripts. 
  The script creates tenant elastic pools that will be used to host tenant databases restored from the original Wingtip location. 

.PARAMETER WingtipRecoveryResourceGroup
  Resource group that will be used to contain recovered resources

.EXAMPLE
  [PS] C:\>.\Replicate-TenantElasticPoolsToRecoveryRegion.ps1 -WingtipRecoveryResourceGrou "sampleResourceGroup"
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

# Get list of tenant elastic pools to be recovered 
$tenantElasticPools = @()
$tenantElasticPools += Get-ExtendedElasticPool -Catalog $tenantCatalog | Where-Object {($_.ServerName -NotMatch "$($config.RecoveryRoleSuffix)$")}

$recoveredPoolCount = 0
$poolCount = $tenantElasticPools.length 
$sleepInterval = 10
$pastDeploymentWaitTime = 0
$deploymentName = "TenantElasticPoolReplication"

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

# Wait until at least one tenant server has been replicated before starting elastic pool replication
$replicatedServers = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers" -ResourceNameContains "tenants"
while (!$replicatedServers)
{
  Write-Output "waiting for tenant server(s) to complete deployment ..."
  Start-Sleep $sleepInterval
  $replicatedServers = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers" -ResourceNameContains "tenants"
}

# Check for elastic pools that have previously been recovered 
$replicatedElasticPools = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers/elasticpools"
foreach ($pool in $tenantElasticPools)
{
  $recoveredServerName = $pool.ServerName + $config.RecoveryRoleSuffix
  $compoundPoolName = "$($recoveredServerName)/$($pool.ElasticPoolName)"
  $pool | Add-Member "CompoundPoolName" $compoundPoolName

  if ($replicatedElasticPools.Name -contains $pool.CompoundPoolName)
  {
    $recoveredPoolCount += 1
  }
}

# Output recovery progress 
$elasticPoolRecoveryPercentage = [math]::Round($recoveredPoolCount/$poolCount,2)
$elasticPoolRecoveryPercentage = $elasticPoolRecoveryPercentage * 100
Write-Output "Deploying ... ($recoveredPoolCount of $poolCount complete)"

# Recover all elastic pools in restored tenant servers 
while ($recoveredPoolCount -lt $poolCount)
{
  $poolRecoveryQueue = @()
  [array]$elasticPoolConfigurations = @()
  $replicatedServers = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers" -ResourceNameContains "tenants"
  $replicatedElasticPools = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers/elasticpools"

  # Generate list of pools that will be recovered in current loop iteration
  foreach($elasticPool in $tenantElasticPools)
  {
    # Add elastic pools that are eligible to be recovered to the pool queue 
    $recoveredServerName = $elasticPool.ServerName + $config.RecoveryRoleSuffix

    if (($replicatedElasticPools.Name -notcontains $elasticPool.CompoundPoolName) -and ($replicatedServers.Name -contains $recoveredServerName))
    {
      $poolRecoveryQueue += $elasticPool
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
    }    

    # Recover tenant elastic pools in queue 
    if ($poolRecoveryQueue.Count -gt 0)
    {
      $deployment = New-AzureRmResourceGroupDeployment `
                      -Name $deploymentName `
                      -ResourceGroupName $recoveryResourceGroup.ResourceGroupName `
                      -TemplateFile ("$using:scriptPath\RecoveryTemplates\" + $config.TenantElasticPoolRestoreBatchTemplate) `
                      -PoolConfigurationObjects $elasticPoolConfigurations `
                      -ErrorAction Stop

      $recoveredPoolCount += $poolRecoveryQueue.length
    }

    # Output recovery progress 
    $elasticPoolRecoveryPercentage = [math]::Round($recoveredPoolCount/$poolCount,2)
    $elasticPoolRecoveryPercentage = $elasticPoolRecoveryPercentage * 100
    Write-Output "Deploying ... ($recoveredPoolCount of $poolCount complete)"      
  }
}

# Output recovery progress 
$elasticPoolRecoveryPercentage = [math]::Round($recoveredPoolCount/$poolCount,2)
$elasticPoolRecoveryPercentage = $elasticPoolRecoveryPercentage * 100
Write-Output "Deployed ($recoveredPoolCount of $poolCount)"  
