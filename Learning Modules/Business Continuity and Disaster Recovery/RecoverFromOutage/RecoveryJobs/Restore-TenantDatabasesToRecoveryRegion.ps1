<#
.SYNOPSIS
  Restores tenant databases in original Wingtip region to recovery region

.DESCRIPTION
  This script is intended to be run as a background job in the 'Restore-IntoSecondaryRegion' script that recovers the Wingtip SaaS app environment (apps, databases, servers e.t.c) into a recovery region.
  The script restores tenant databases from automatic backups taken in the original Wingtip location. 

.PARAMETER WingtipRecoveryResourceGroup
  Resource group that will be used to contain recovered resources

.PARAMETER TotalBatchMax
  Number of tenant databases that will be restored in parallel at a time

.PARAMETER PoolBatchMax
  Number of tenant databases that will be restored into an elastic pool in parallel at a time.

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
    [int] $PoolBatchMax=5 
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

# Get list of tenant databases to be recovered. 
[array]$tenantDatabaseConfigurations = @()
$tenantDatabases = @()
$tenantDatabases += Get-ExtendedDatabase -Catalog $tenantCatalog | Where-Object {($_.ServerName -NotMatch "$($config.RecoverySuffix)$")}
$tenantPriorityList = Get-ExtendedTenant -Catalog $tenantCatalog -SortTenants | Where-Object {($_.ServerName -NotMatch "$($config.RecoverySuffix)$")}

# Add tenant priority to tenant databases 
foreach ($database in $tenantDatabases)
{
  $databasePriority = ($tenantPriorityList | Where-Object {($_.ServerName -eq $database.ServerName) -and ($_.DatabaseName -eq $database.DatabaseName)}).ServicePlan
  $database | Add-Member "ServicePlan" $databasePriority
}

$tenantDatabaseCount = $tenantDatabases.length 
$recoveredDatabaseCount = 0
$recoveryBatch = 0
$sleepInterval = 10
$pastDeploymentWaitTime = 0

# Wait until all elastic pools have been restored to start restoring databases
# This ensures that all required container resources have been acquired before database recovery begins 
$nonRecoveredPoolList = Get-ExtendedElasticPool -Catalog $tenantCatalog | Where-Object {($_.ServerName -NotMatch "$($config.RecoverySuffix)$") -and ($_.RecoveryState -NotIn 'restored')}
while ($nonRecoveredPoolList)
{
  Start-Sleep $sleepInterval
  $nonRecoveredPoolList = Get-ExtendedElasticPool -Catalog $tenantCatalog | Where-Object {($_.ServerName -NotMatch "$($config.RecoverySuffix)$") -and ($_.RecoveryState -NotIn 'restored')}
}

# Restore tenant databases while there are databases to restore
while ($recoveredDatabaseCount -lt $tenantDatabaseCount)
{
  # Find any previous database recovery operations to get most current state of recovered resources 
  # This allows the script to be re-run if an error during deployment 
  $pastDeployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $WingtipRecoveryResourceGroup -Name "TenantDatabaseRecovery-Pri$recoveryBatch" -ErrorAction SilentlyContinue 2>$null

  # Wait for past deployment to complete if it's still active 
  while (($pastDeployment) -and ($pastDeployment.ProvisioningState -NotIn "Succeeded", "Failed", "Canceled"))
  {
    # Wait for no more than 5 minutes (300 secs) for previous deployment to complete
    if ($pastDeploymentWaitTime -lt 300)
    {
        Write-Output "Waiting for previous deployment to complete ..."
        Start-Sleep $sleepInterval
        $pastDeploymentWaitTime += $sleepInterval
        $pastDeployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $WingtipRecoveryResourceGroup -Name "TenantDatabaseRecovery-Pri$recoveryBatch" -ErrorAction SilentlyContinue 2>$null    
    }
    else
    {
        Stop-AzureRmResourceGroupDeployment -ResourceGroupName $WingtipRecoveryResourceGroup -Name "TenantDatabaseRecovery-Pri$recoveryBatch" -ErrorAction SilentlyContinue 1>$null 2>$null
        break
    }
    
  }

  # Get databases to be recovered 
  $recoveryQueue = $tenantDatabases | Where-Object {$_.RecoveryState -In 'n/a','restoring','complete'}
  $restoredDatabases = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers/databases"
  $restoredDatabaseNames = (($restoredDatabases.Name) -split ".+/") | ?{$_}

  # Check to make sure databases in queue have not already been recovered
  foreach ($database in $recoveryQueue)
  {
    if ($restoredDatabaseNames -contains $database.DatabaseName)
    {
      $restoredServerName = $database.ServerName + $config.RecoverySuffix

      # Enable change tracking on tenant database. This tracks any changes to tenant data that will need to be repatriated when the primary region is available once more. 
      Enable-ChangeTrackingForTenant -Catalog $tenantCatalog -TenantServerName $restoredServerName -TenantDatabaseName $database.DatabaseName -RetentionPeriod 10

      # Mark database as restored 
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endRecovery" -ServerName $database.ServerName -DatabaseName $database.DatabaseName
     
      # Remove database from queue 
      $recoveryQueue = $recoveryQueue -ne $database
    }
  }
  
  # Output recovery progress 
  $recoveredDatabaseCount = $tenantDatabaseCount - $recoveryQueue.Length
  $DatabaseRecoveryPercentage = [math]::Round($recoveredDatabaseCount/$tenantDatabaseCount,2)
  $DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
  Write-Output "$DatabaseRecoveryPercentage% ($($recoveredDatabaseCount) of $tenantDatabaseCount)"

  # Select the highest priority tenant databases up to batch max. 
  # If the databases will be recovered into a pool, they are also subject to a pool batch in order to not exhaust elastic pool limits
  if ($recoveryQueue.Count -gt 0)
  {
    $databaseBatch = @()
    $tenantPriorityOrder = "Premium", "Standard", "Free"
    $tenantSort = {
      $rank = $tenantPriorityOrder.IndexOf($($_.ServicePlan.ToLower()))
      if ($rank -ne -1) { $rank }
      else { [System.Double]::PositiveInfinity }
    }

    # Group databases to be restored by elastic pool names 
    $recoveryQueueByPool = $recoveryQueue | group {($_.ServerName + '/' + $_.ElasticPoolName)} -AsHashTable -AsString 

    # Grab databases to be recovered (up to poolMax variable) from each available pool
    foreach ($pool in $recoveryQueueByPool.Keys)
    {
      $databasePriorityList = $recoveryQueueByPool[$pool] | sort $tenantSort
      if ($databaseBatch.Length -lt $TotalBatchMax)
      {
        if (($databaseBatch.Length + $PoolBatchMax) -lt $TotalBatchMax)
        {
          $endIndex = $PoolBatchMax -1
          $databaseBatch += $databasePriorityList[0..$endIndex]
        }
        else
        {
          $endIndex = $TotalBatchMax - $databaseBatch.Length -1
          $databaseBatch += $databasePriorityList[0..$endIndex]
        }        
      }
    }

    # Add any available standalone databases to the recovery batch if the batch is not completely full
    $standalonePool = $recoveryQueueByPool.Keys -match "^[a-zA-Z0-9_.-]+/$"
    if (($databaseBatch.Length -lt $TotalBatchMax) -and $standalonePool)
    {
      $databasePriorityList = $recoveryQueueByPool[$standalonePool] | sort $tenantSort
      $currentIndex = 0
      while (($databaseBatch.Length -ne $TotalBatchMax) -and ($currentIndex -le $databasePriorityList.Length))
      {
        $currentDatabase = $databasePriorityList[$currentIndex]
        if ($databaseBatch -notcontains $currentDatabase)
        {
          $databaseBatch += $currentDatabase
        }
        $currentIndex += 1
      }
    }
    
    # Record database configuration of tenant databases in batch 
    foreach ($tenantDatabase in $databaseBatch)
    {
      $recoveredServer = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceNameEquals ($tenantDatabase.ServerName + $config.RecoverySuffix)
      $databaseId = "/subscriptions/$currentSubscriptionId/resourceGroups/$($wtpUser.ResourceGroupName)/providers/Microsoft.Sql/servers/$($tenantDatabase.ServerName)/recoverabledatabases/$($tenantDatabase.DatabaseName)"
      $serviceObjective = ' '
      if ($tenantDatabase.ServiceObjective -ne 'ElasticPool')
      {
          $serviceObjective = $tenantDatabase.ServiceObjective
      }

      [array]$tenantDatabaseConfigurations += @{
          ServerName = "$($recoveredServer.Name)"
          Location = "$($recoveredServer.Location)"
          DatabaseName = "$($tenantDatabase.DatabaseName)"
          ServiceObjective = "$serviceObjective"
          ElasticPoolName = "$($tenantDatabase.ElasticPoolName)"         
          SourceDatabaseId = "$databaseId"
      }
        
      # Update tenant database recovery state 
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startRecovery" -ServerName $tenantDatabase.ServerName -DatabaseName $tenantDatabase.DatabaseName
    }
  }

  if ($databaseBatch.Count -gt 0)
  {
    # Restore tenant databases in batch (blocking call)
    $deployment = New-AzureRmResourceGroupDeployment `
                    -Name "TenantDatabaseRecovery-Pri$recoveryBatch" `
                    -ResourceGroupName $recoveryResourceGroup.ResourceGroupName `
                    -TemplateFile ("$using:scriptPath\RecoveryTemplates\" + $config.TenantDatabaseRestoreBatchTemplate) `
                    -DatabaseConfigurationObjects $tenantDatabaseConfigurations `
                    -ErrorAction Stop

    # Mark databases as restored 
    foreach ($tenantDatabase in $databaseBatch)
    {
      $restoredServerName = $tenantDatabase.ServerName + $config.RecoverySuffix

      # Enable change tracking on tenant database. This tracks any changes to tenant data that will need to be repatriated when the primary region is available once more. 
      Enable-ChangeTrackingForTenant -Catalog $tenantCatalog -TenantServerName $restoredServerName -TenantDatabaseName $tenantDatabase.DatabaseName -RetentionPeriod 10

      # Update tenant database recovery state
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endRecovery" -ServerName $tenantDatabase.ServerName -DatabaseName $tenantDatabase.DatabaseName
    }

    $recoveredDatabaseCount += $databaseBatch.Count
    $recoveryBatch += 1    
  }

  # Output recovery progress 
  $DatabaseRecoveryPercentage = [math]::Round($recoveredDatabaseCount/$tenantDatabaseCount,2)
  $DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
  Write-Output "$DatabaseRecoveryPercentage% ($($recoveredDatabaseCount) of $tenantDatabaseCount)"
}

# Output recovery progress 
$DatabaseRecoveryPercentage = [math]::Round($tenantDatabaseCount/$tenantDatabaseCount,2)
$DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
Write-Output "$DatabaseRecoveryPercentage% ($($tenantDatabaseCount) of $tenantDatabaseCount)"

