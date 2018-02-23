<#
.SYNOPSIS
  Restores tenant databases in original Wingtip region to recovery region

.DESCRIPTION
  This script is intended to be run as a background job in the 'Restore-IntoSecondaryRegion' script that recovers the Wingtip SaaS app environment (apps, databases, servers e.t.c) into a recovery region.
  The script restores tenant databases from automatic backups taken in the original Wingtip location. 

.PARAMETER WingtipRecoveryResourceGroup
  Resource group that will be used to contain recovered resources

.PARAMETER TotalBatchMax
  Maximum number of tenant databases that can be restored in parallel in a batch

.PARAMETER PoolBatchMax
  Maximum number of tenant databases that can be restored into an elastic pool in parallel in a batch.

.PARAMETER ConcurrentBatchMax
  Maximum number of batches that can be run concurrently

.EXAMPLE
  [PS] C:\>.\Restore-TenantDatabasesToRecoveryRegion.ps1 -WingtipRecoveryResourceGroup "sampleRecoveryResourceGroup"
#>
[cmdletbinding()]
param (
    [parameter(Mandatory=$true)]
    [String] $WingtipRecoveryResourceGroup,

    [parameter(Mandatory=$false)]
    [int] $TotalBatchMax=15,

    [parameter(Mandatory=$false)]
    [int] $PoolBatchMax=5,

    [parameter(Mandatory=$false)]
    [int] $ConcurrentBatchMax=5
)

Import-Module "$using:scriptPath\..\..\Common\CatalogAndDatabaseManagement" -Force
Import-Module "$using:scriptPath\..\..\WtpConfig" -Force
Import-Module "$using:scriptPath\..\..\UserConfig" -Force

# Import-Module "$PSScriptRoot\..\..\..\Common\CatalogAndDatabaseManagement" -Force
# Import-Module "$PSScriptRoot\..\..\..\WtpConfig" -Force
# Import-Module "$PSScriptRoot\..\..\..\UserConfig" -Force

# Stop execution on error 
$ErrorActionPreference = "Stop"
  
# Login to Azure subscription
$credentialLoad = Import-AzureRmContext -Path "$env:TEMP\profile.json"
if (!$credentialLoad)
{
    Initialize-Subscription
}

# Get deployment configuration  
$sleepInterval = 10
$wtpUser = Get-UserConfig
$config = Get-Configuration
$currentSubscriptionId = Get-SubscriptionId

# Initialize database recovery variables
$batchNumber = 0
$deploymentQueue = @()

# -------------------- Helper Functions -----------------------------------------
<#
 .SYNOPSIS  
  Returns the highest priority tenants per elastic pool.
  Tenants are grouped into a batch until the 'PoolBatchMax' limit is reached
#>
function Select-HighestPriorityPoolTenants
{
  param
  (
    [Parameter(Mandatory=$true)]
    [array]$InputDatabaseList    
  )

  $databaseBatch = @()
  $tenantPriorityOrder = "Premium", "Standard", "Free"
  $tenantSortFunction = {
    $rank = $tenantPriorityOrder.IndexOf($($_.ServicePlan.ToLower()))
    if ($rank -ne -1) { $rank } else { [System.Double]::PositiveInfinity }
  }

  # Select eligible databases for recovery
  $recoveryQueue = $InputDatabaseList | Where-Object {$_.RecoveryState -In 'n/a', 'errorState', 'complete'}

  # Group databases by elastic pool
  $recoveryQueueByPool = $recoveryQueue | group {($_.ServerName + '/' + $_.ElasticPoolName)} -AsHashTable -AsString

  if ($recoveryQueueByPool.Count -gt 0)
  {
    foreach ($pool in $recoveryQueueByPool.Keys)
    {
      # Sort databases in pool by tenant priority
      $poolPriorityList = $recoveryQueueByPool[$pool] | sort $tenantSortFunction
        
      # Add highest priority tenants in a batch till batch limit is reached
      if (($databaseBatch.Length + $PoolBatchMax) -lt $TotalBatchMax)
      {
        $endIndex = $PoolBatchMax -1
        $databaseBatch += $poolPriorityList[0..$endIndex]
      }
      elseif ($databaseBatch.Length -lt $TotalBatchMax)
      {
        $endIndex = $TotalBatchMax - $databaseBatch.Length -1
        $databaseBatch += $poolPriorityList[0..$endIndex]
      }    
    }
    return $databaseBatch
  }
  else
  {
    return $null
  } 
}

<#
 .SYNOPSIS  
  Submits an ARM deployment to restore input databases into recovery region.
  This function creates a background job that is used to track the status of the deployment in the main script.
#>
function Start-RecoveryBatch
{
  param
  (
    [Parameter(Mandatory=$true)]
    [int]$BatchNumber,

    [Parameter(Mandatory=$true)]
    [array]$OfflineDatabaseList       
  )

  [array]$DatabaseProperties = @()
  $deploymentId = $null

  # Select databases that will be grouped in current recovery batch
  $recoveryBatch = Select-HighestPriorityPoolTenants -InputDatabaseList $offlineDatabaseList
  
  # Deploy recovery databases when applicable
  if ($recoveryBatch.Count -gt 0)
  {
    # Record database configuration of tenant databases in batch 
    foreach ($tenantDatabase in $recoveryBatch)
    {
      $recoveredServerName = ($tenantDatabase.ServerName -split $config.OriginRoleSuffix)[0] + $config.RecoveryRoleSuffix
      $recoveredServer = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceNameEquals $recoveredServerName
      $databaseId = "/subscriptions/$currentSubscriptionId/resourceGroups/$($wtpUser.ResourceGroupName)/providers/Microsoft.Sql/servers/$($tenantDatabase.ServerName)/recoverabledatabases/$($tenantDatabase.DatabaseName)"
      $serviceObjective = ' '
      if ($tenantDatabase.ServiceObjective -ne 'ElasticPool')
      {
          $serviceObjective = $tenantDatabase.ServiceObjective
      }

      $databaseConfiguration = @{}
      $databaseConfiguration.Add("ServerName", "$($recoveredServer.Name)")
      $databaseConfiguration.Add("Location", "$($recoveredServer.Location)")
      $databaseConfiguration.Add("DatabaseName", "$($tenantDatabase.DatabaseName)")
      $databaseConfiguration.Add("ServiceObjective", "$serviceObjective")
      $databaseConfiguration.Add("ElasticPoolName", "$($tenantDatabase.ElasticPoolName)")
      $databaseConfiguration.Add("SourceDatabaseId", "$databaseId")

      [array]$DatabaseProperties += $databaseConfiguration
              
      # Update tenant database recovery state 
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startRecovery" -ServerName $tenantDatabase.ServerName -DatabaseName $tenantDatabase.DatabaseName
    }
  
    # Deploy tenant recovery databases in background job
    $deploymentId = New-AzureRmResourceGroupDeployment `
                      -Name "TenantDatabaseRecovery-Pri$BatchNumber" `
                      -ResourceGroupName $WingtipRecoveryResourceGroup `
                      -TemplateFile ("$using:scriptPath\..\RecoveryTemplates\" + $config.TenantDatabaseRestoreBatchTemplate) `
                      -TemplateParameterObject @{"DatabaseConfigurationObjects"=$DatabaseProperties} `
                      -ErrorAction Stop `
                      -AsJob                      
  }
  
  return $deploymentId
}

## -------------------------------- Main Script ------------------------------------------------

# Get the recovery region resource group
$recoveryResourceGroup = Get-AzureRmResourceGroup -Name $WingtipRecoveryResourceGroup

# Get the tenant catalog in the recovery region
$tenantCatalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name
while ($tenantCatalog.Database.ResourceGroupName -ne $recoveryResourceGroup.ResourceGroupName)
{
  # Sleep for 10s to allow DNS alias for catalog to update to recovery region
  Start-Sleep $sleepInterval
  # Get the active tenant catalog
  $tenantCatalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name
}

# Wait until all elastic pools have been restored to start restoring databases
# This ensures that all required container resources have been acquired before database recovery begins 
$nonRecoveredPoolList = Get-ExtendedElasticPool -Catalog $tenantCatalog | Where-Object {($_.ServerName -NotMatch "$($config.RecoveryRoleSuffix)$") -and ($_.RecoveryState -NotIn 'restored')}
while ($nonRecoveredPoolList)
{
  Start-Sleep $sleepInterval
  $nonRecoveredPoolList = Get-ExtendedElasticPool -Catalog $tenantCatalog | Where-Object {($_.ServerName -NotMatch "$($config.RecoveryRoleSuffix)$") -and ($_.RecoveryState -NotIn 'restored')}
}

# Find previous deployments that are not yet complete
# This allows the script to be re-run if an error occurs during deployment
$recoveringDatabases = @()
$recoveringDatabases += Get-ExtendedDatabase -Catalog $tenantCatalog | Where-Object {($_.RecoveryState -eq "restoring")}
if ($recoveringDatabases.Count -gt 0)
{
  # Find any ongoing ARM deployments for database recovery operations
  $ongoingDeployments = @()
  $ongoingDeployments += Get-AzureRmResourceGroupDeployment -ResourceGroupName $WingtipRecoveryResourceGroup | Where-Object {(($_.DeploymentName -Match "TenantDatabaseRecovery*") -and ($_.ProvisioningState -NotIn "Succeeded", "Failed", "Canceled"))}

  if ($ongoingDeployments.Count -gt 0)
  {
    # Add ongoing deployments to queue of background jobs that will be monitored
    foreach ($deployment in $ongoingDeployments)
    {
      $jobObject = @{
        Id = -100
        Name = $deployment.DeploymentName
        State = $deployment.ProvisioningState
      }     

      $deploymentQueue += $jobObject
    }

  }
  else
  {
    # Get all tenant databases that have been restored into the recovery region 
    $recoveredDatabaseInstances = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers/databases" -ResourceNameContains "tenants*"

    # Update recovery state of databases
    foreach ($database in $recoveringDatabases)
    {
      if ($recoveredDatabaseInstances.Name -match $database.DatabaseName)
      {
        # Enable change tracking on tenant database. This tracks any changes to tenant data that will need to be repatriated when the primary region is available once more. 
        $restoredServerName = ($database.ServerName -split $config.OriginRoleSuffix)[0] + $config.RecoveryRoleSuffix
        Enable-ChangeTrackingForTenant -Catalog $tenantCatalog -TenantServerName $restoredServerName -TenantDatabaseName $database.DatabaseName -RetentionPeriod 10

        # Mark database as restored 
        $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endRecovery" -ServerName $database.ServerName -DatabaseName $database.DatabaseName
      }
      else
      {
        # Mark errorState for databases that have not been recovered 
        $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "markError" -ServerName $database.ServerName -DatabaseName $database.DatabaseName
      }
    }
  }
}

# Construct list of tenant databases to be recovered 
$tenantDatabases = @()
$tenantDatabases += Get-ExtendedDatabase -Catalog $tenantCatalog
$offlineTenantDatabases = $tenantDatabases | Where-Object {($_.ServerName -NotMatch "$($config.RecoveryRoleSuffix)$")}

# Add 'service plan' property to tenant database list. 
# This will be used to calculate database recovery priority
$tenantList = Get-ExtendedTenant -Catalog $tenantCatalog
foreach ($database in $offlineTenantDatabases)
{
  $databaseServicePlan = ($tenantList | Where-Object {($_.ServerName -eq $database.ServerName) -and ($_.DatabaseName -eq $database.DatabaseName)}).ServicePlan
  $database | Add-Member "ServicePlan" $databaseServicePlan
}

# Output recovery progress 
$tenantDatabaseCount = $tenantDatabases.length 
$recoveredDatabaseCount = $tenantDatabaseCount - $offlineTenantDatabases.length
$DatabaseRecoveryPercentage = [math]::Round($recoveredDatabaseCount/$tenantDatabaseCount,2)
$DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
Write-Output "$DatabaseRecoveryPercentage% ($($recoveredDatabaseCount) of $tenantDatabaseCount)"

# Restore tenant databases in batches using ARM templates
for ($batch=0; $batch -lt $ConcurrentBatchMax; $batch++)
{
  $batchNumber = $batch
  
  # Deploy tenant recovery databases in background job
  $deploymentId = Start-RecoveryBatch -BatchNumber $batchNumber -OfflineDatabaseList $offlineTenantDatabases

  if ($deploymentId)
  {
    $deploymentQueue += $deploymentId
    
    # Fetch most recent database recovery status
    $offlineTenantDatabases = Get-ExtendedDatabase -Catalog $tenantCatalog | Where-Object {($_.ServerName -NotMatch "$($config.RecoveryRoleSuffix)$")}    
  }
  else 
  {
    # There are no databases eligible for recovery     
    break
  }
}

# Check on status of database recovery deployments 
while ($deploymentQueue.Count -gt 0)
{
  foreach($recoveryJob in $deploymentQueue)
  {
    # Monitor the status of previous ongoing deployments
    if ($recoveryJob.Id -eq -100)
    {
      $deploymentDetails = Get-AzureRmResourceGroupDeployment -ResourceGroupName $WingtipRecoveryResourceGroup -DeploymentName $recoveryJob.Name

      if ($deploymentDetails.ProvisioningState -eq "Completed")
      {
        # Get list of databases in batch 
        $databaseObjects = ($deploymentDetails.databaseConfigurationObjects.Value.ToString() | ConvertFrom-Json)

        foreach ($tenantDatabase in $databaseObjects)
        {
          $restoredServerName = ($tenantDatabase.ServerName -split $config.OriginRoleSuffix)[0] + $config.RecoveryRoleSuffix

          # Enable change tracking on tenant database. This tracks any changes to tenant data that will need to be repatriated when the primary region is available once more. 
          Enable-ChangeTrackingForTenant -Catalog $tenantCatalog -TenantServerName $restoredServerName -TenantDatabaseName $tenantDatabase.DatabaseName -RetentionPeriod 10

          # Update tenant database recovery state
          $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endRecovery" -ServerName $tenantDatabase.ServerName -DatabaseName $tenantDatabase.DatabaseName

          # Output recovery progress 
          $recoveredDatabaseCount+= 1
          $DatabaseRecoveryPercentage = [math]::Round($recoveredDatabaseCount/$tenantDatabaseCount,2)
          $DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
          Write-Output "$DatabaseRecoveryPercentage% ($($recoveredDatabaseCount) of $tenantDatabaseCount)"
        }

        # Remove completed job from queue for polling
        $deploymentQueue = $deploymentQueue -ne $recoveryJob 
      }
      elseif ($deploymentDetails.ProvisioningState -eq "Failed")
      {
        $deploymentQueue = $deploymentQueue -ne $recoveryJob
      }      
    }
    elseif ($recoveryJob.State -eq "Completed")
    {
      # Start new recovery batch if there are any databases left to recover
      $recoveryBatch = Select-HighestPriorityPoolTenants -InputDatabaseList $offlineTenantDatabases
      if ($recoveryBatch.Count -gt 0)
      {
        $batchNumber+= 1
        $deploymentId = Start-RecoveryBatch -BatchNumber $batchNumber -OfflineDatabaseList $offlineTenantDatabases
        $deploymentQueue += $deploymentId

        # Fetch most recent database recovery status
        $offlineTenantDatabases = Get-ExtendedDatabase -Catalog $tenantCatalog | Where-Object {($_.ServerName -NotMatch "$($config.RecoveryRoleSuffix)$")}      
      }
      
      # Get recovery job details
      $recoveryJobDetails = Receive-Job $recoveryJob
      $deploymentName = $recoveryJobDetails.DeploymentName
      
      # Get list of databases in batch 
      $deploymentDetails = Get-AzureRmResourceGroupDeployment -ResourceGroupName $WingtipRecoveryResourceGroup -DeploymentName $deploymentName
      $databaseObjects = ($deploymentDetails.Parameters.databaseConfigurationObjects.Value.ToString() | ConvertFrom-Json)

      foreach ($tenantDatabase in $databaseObjects)
      {
        $originServerName = ($tenantDatabase.ServerName -split $config.RecoveryRoleSuffix)[0] + $config.OriginRoleSuffix
        $restoredServerName = $tenantDatabase.ServerName

        # Enable change tracking on tenant database. This tracks any changes to tenant data that will need to be repatriated when the primary region is available once more. 
        Enable-ChangeTrackingForTenant -Catalog $tenantCatalog -TenantServerName $restoredServerName -TenantDatabaseName $tenantDatabase.DatabaseName -RetentionPeriod 10

        # Update tenant database recovery state
        $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endRecovery" -ServerName $originServerName -DatabaseName $tenantDatabase.DatabaseName

        # Output recovery progress 
        $recoveredDatabaseCount+= 1
        $DatabaseRecoveryPercentage = [math]::Round($recoveredDatabaseCount/$tenantDatabaseCount,2)
        $DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
        Write-Output "$DatabaseRecoveryPercentage% ($($recoveredDatabaseCount) of $tenantDatabaseCount)"
      }

      # Remove completed job from queue for polling
      $deploymentQueue = $deploymentQueue -ne $recoveryJob         
    }
    elseif ($recoveryJob.State -eq "Failed")
    {
      # Remove completed job from queue for polling
      $deploymentQueue = $deploymentQueue -ne $recoveryJob
    }
  }
}

# Output recovery progress 
$DatabaseRecoveryPercentage = [math]::Round($recoveredDatabaseCount/$tenantDatabaseCount,2)
$DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
Write-Output "$DatabaseRecoveryPercentage% ($($recoveredDatabaseCount) of $tenantDatabaseCount)"
