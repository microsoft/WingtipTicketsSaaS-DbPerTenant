<#
.SYNOPSIS
  Restores tenant databases in original Wingtip region to recovery region

.DESCRIPTION
  This script is intended to be run as a background job in the 'Restore-IntoSecondaryRegion' script that recovers the Wingtip SaaS app environment (apps, databases, servers e.t.c) into a recovery region.
  The script restores tenant databases from automatic backups taken in the original Wingtip location. 

.PARAMETER WingtipRecoveryResourceGroup
  Resource group that will be used to contain recovered resources

.PARAMETER MaxConcurrentRestoreOperations
  Maximum number of restore operations that can be run concurrently

.EXAMPLE
  [PS] C:\>.\Restore-TenantDatabasesToRecoveryRegion.ps1 -WingtipRecoveryResourceGroup "sampleRecoveryResourceGroup"
#>
[cmdletbinding()]
param (
    [parameter(Mandatory=$true)]
    [String] $WingtipRecoveryResourceGroup,    

    [parameter(Mandatory=$false)]
    [int] $MaxConcurrentRestoreOperations=200
)

Import-Module "$using:scriptPath\..\..\Common\CatalogAndDatabaseManagement" -Force
Import-Module "$using:scriptPath\..\..\Common\AzureSqlAsyncManagement" -Force
Import-Module "$using:scriptPath\..\..\WtpConfig" -Force
Import-Module "$using:scriptPath\..\..\UserConfig" -Force

# Import-Module "$PSScriptRoot\..\..\..\Common\CatalogAndDatabaseManagement" -Force
# Import-Module "$PSScriptRoot\..\..\..\Common\AzureSqlAsyncManagement" -Force
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
$operationQueue = @()
$operationQueueMap = @{}

# -------------------- Helper Functions -----------------------------------------
<#
 .SYNOPSIS  
  Returns the highest priority tenant that does not have a recovery database.
  Tenants are grouped by elastic pool and selected from the input catalog database. 
  Tenants not in an elastic pool are grouped by servername.
#>
function Select-HighestPriorityUnrecoveredTenantPerPool
{
  param
  (
    [parameter(Mandatory=$true)]
    [object]$Catalog   
  )

  $highestPriorityTenants = @{}
  $tenantList = Get-ExtendedTenant -Catalog $tenantCatalog
  $tenantPriorityOrder = "Premium", "Standard", "Free"
  $tenantSortFunction = {
    $rank = $tenantPriorityOrder.IndexOf($($_.ServicePlan.ToLower()))
    if ($rank -ne -1) { $rank } else { [System.Double]::PositiveInfinity }
  }

  # Select databases eligible for recovery
  $unrecoveredTenantList = @()
  $unrecoveredTenantList += Get-ExtendedDatabase -Catalog $Catalog | Where-Object {($_.ServerName -NotMatch "$($config.RecoveryRoleSuffix)$")}
  $recoveryQueue = $unrecoveredTenantList | Where-Object {$_.RecoveryState -In 'n/a', 'errorState', 'complete'}

  # Add 'service plan' property to tenant database list. This will be used to calculate database recovery priority
  foreach ($database in $recoveryQueue)
  {
    $databaseServicePlan = ($tenantList | Where-Object {($_.ServerName -eq $database.ServerName) -and ($_.DatabaseName -eq $database.DatabaseName)}).ServicePlan
    $database | Add-Member "ServicePlan" $databaseServicePlan
  }

  # Group databases by elastic pool
  $recoveryQueueByPool = $recoveryQueue | Group-Object {($_.ServerName + '/' + $_.ElasticPoolName)} -AsHashTable -AsString

  if ($recoveryQueueByPool.Count -gt 0)
  {
    foreach ($pool in $recoveryQueueByPool.Keys)
    {
      # Sort databases in pool by tenant priority
      $poolPriorityList = $recoveryQueueByPool[$pool] | Sort-Object $tenantSortFunction
        
      # Select highest priority tenant for current pool
      if (!$highestPriorityTenants.ContainsKey($pool))
      {
        $highestPriorityTenants.Add($pool, $poolPriorityList[0])
      }
    }
    return $highestPriorityTenants
  }
  else
  {
    return $null
  } 
}

<#
 .SYNOPSIS  
  Starts an asynchronous call to georestore a tenant database
  This function returns a task object that can be used to track the status of the operation
#>
function Start-AsynchronousDatabaseRecovery
{
  param
  (
    [Parameter(Mandatory=$true)]
    [Microsoft.Azure.Management.Sql.Fluent.SqlManager]$AzureContext,

    [Parameter(Mandatory=$true)]
    [object]$TenantDatabase       
  )

  # Construct geo-restore parameters
  $recoveredServerName = ($TenantDatabase.ServerName -split $config.OriginRoleSuffix)[0] + $config.RecoveryRoleSuffix
  $recoveredServer = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceNameEquals $recoveredServerName
  $databaseId = "/subscriptions/$currentSubscriptionId/resourceGroups/$($wtpUser.ResourceGroupName)/providers/Microsoft.Sql/servers/$($TenantDatabase.ServerName)/recoverabledatabases/$($TenantDatabase.DatabaseName)"

  if ($TenantDatabase.ServiceObjective -eq 'ElasticPool')
  {
    # Geo-restore tenant database into an elastic pool
    $taskObject = Invoke-AzureSQLDatabaseGeoRestoreAsync `
                    -AzureContext $AzureContext `
                    -ResourceGroupName $WingtipRecoveryResourceGroup `
                    -Location $recoveredServer.Location `
                    -ServerName $recoveredServerName `
                    -DatabaseName $TenantDatabase.DatabaseName `
                    -SourceDatabaseId $databaseId `
                    -ElasticPoolName $TenantDatabase.ElasticPoolName
  }
  else
  {
    # Geo-restore tenant database into a standalone database
    $taskObject = GeoRestore-AzureSQLDatabaseAsync `
                  -AzureContext $AzureContext `
                  -ResourceGroupName $WingtipRecoveryResourceGroup `
                  -Location $recoveredServer.Location `
                  -ServerName $recoveredServerName `
                  -DatabaseName $TenantDatabase.DatabaseName `
                  -SourceDatabaseId $databaseId `
                  -RequestedServiceObjectiveName $TenantDatabase.ServiceObjective
  }  
  return $taskObject
}

<#
 .SYNOPSIS  
  Marks a tenant database recovery as complete when the database has been successfully geo-restored
#>
function Complete-AsynchronousDatabaseRecovery
{
  param
  (
    [Parameter(Mandatory=$true)]
    [String]$RecoveryJobId
  )

  $databaseDetails = $operationQueueMap[$RecoveryJobId]
  if ($databaseDetails)
  {
    $originServerName = $databaseDetails.ServerName
    $restoredServerName = ($databaseDetails.ServerName -split $config.OriginRoleSuffix)[0] + $config.OriginRoleSuffix

    # Update tenant database recovery state
    $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endRecovery" -ServerName $originServerName -DatabaseName $databaseDetails.DatabaseName
    if (!$dbState)
    {
      Write-Verbose "Could not update recovery state for database: '$originServerName/$($databaseDetails.DatabaseName)'"
    }
  }
  else
  {
    Write-Verbose "Could not find database details for recovery job with Id: '$RecoveryJobId'"
  }

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
  # Get past database operations that occurred in the recovery resource group
  $operationsLog = Get-AzureRmLog -ResourceGroupName $WingtipRecoveryResourceGroup -StartTime (Get-Date).AddDays(-1) -MaxRecord 200 3>$null | Where-Object {($_.OperationName.Value -eq 'Microsoft.Sql/servers/databases/write')}
  $operationsLog = $operationsLog | Group-Object -Property 'CorrelationId'

  # Find all ongoing database recovery operations
  $ongoingDeployments = @()  
  foreach ($operationSequence in $operationsLog)
  {
    if ($operationSequence.Group.EventName.Value -notcontains "EndRequest")
    {
      $operation = $operationSequence.Group | Where-Object {$_.EventName.Value -eq "BeginRequest"}
      $ongoingDeployments += $operation
    }
  }

  if ($ongoingDeployments.Count -gt 0)
  {
    # Add ongoing deployments to queue of background jobs that will be monitored
    foreach ($deployment in $ongoingDeployments)
    {
      $jobObject = [PSCustomObject]@{
        Id = $deployment.CorrelationId
        ResourceId = $deployment.ResourceId
        State = $deployment.Status.Value
        EventTimestamp = $deployment.EventTimestamp
      }

      $tenantServerName = [regex]::match($deployment.ResourceId,'/servers/([\w-]+)/').Groups[1].Value
      $tenantDatabaseName = [regex]::match($test,'/databases/([\w-]+)').Groups[1].Value
      $databaseDetails = @{
        "ServerName" = $tenantServerName
        "DatabaseName" = $tenantDatabaseName
        "ServiceObjective" = $null
        "ElasticPoolName" = $null
      }     

      $jobId = $jobObject.Id
      if (!$operationQueueMap.ContainsKey("$jobId"))
      {
        $operationQueue += $jobObject
        $operationQueueMap.Add("$jobId", $databaseDetails)
      }
    }
  }
  
  # Get all tenant databases that have been restored into the recovery region 
  $recoveredDatabaseInstances = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers/databases" -ResourceNameContains "tenants"

  # Update recovery state of databases
  foreach ($database in $recoveringDatabases)
  {
    if ($recoveredDatabaseInstances.Name -match $database.DatabaseName)
    {
        # Mark database as restored
        $recoveredDatabaseCount +=1 
        $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endRecovery" -ServerName $database.ServerName -DatabaseName $database.DatabaseName
    }
    else
    {
        # Mark errorState for databases that have not been recovered 
        $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "markError" -ServerName $database.ServerName -DatabaseName $database.DatabaseName
    }
  }  
}

# Get list of tenant databases to be recovered 
$tenantDatabases = @()
$tenantDatabases += Get-ExtendedDatabase -Catalog $tenantCatalog | Where-Object {($_.ServerName -notmatch "$($config.RecoveryRoleSuffix)$")}
$offlineTenantDatabases = $tenantDatabases | Where-Object {(($_.ServerName -NotMatch "$($config.RecoveryRoleSuffix)$") -and ($_.RecoveryState -NotIn 'restored', 'failedOver', 'complete'))}

# Output recovery progress 
$tenantDatabaseCount = $tenantDatabases.length 
$recoveredDatabaseCount = $tenantDatabaseCount - $offlineTenantDatabases.length
$DatabaseRecoveryPercentage = [math]::Round($recoveredDatabaseCount/$tenantDatabaseCount,2)
$DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
Write-Output "$DatabaseRecoveryPercentage% ($($recoveredDatabaseCount) of $tenantDatabaseCount)"

# Issue a request to restore tenant databases asynchronously till concurrent operation limit is reached
$azureContext = Get-RestAPIContext
while($operationQueue.Count -le $MaxConcurrentRestoreOperations)
{
  $tenantListPerPool = Select-HighestPriorityUnrecoveredTenantPerPool -Catalog $tenantCatalog

  if ($tenantListPerPool)
  {
    # Recover the highest priority tenant in each available elastic pool
    foreach ($elasticPool in $tenantListPerPool.Keys)
    {
      $tenantDatabase = $tenantListPerPool[$elasticPool]

      # Update tenant database recovery state
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startRecovery" -ServerName $tenantDatabase.ServerName -DatabaseName $tenantdatabase.DatabaseName

      $operationObject = Start-AsynchronousDatabaseRecovery -AzureContext $azureContext -TenantDatabase $tenantDatabase
      $databaseDetails = @{
        "ServerName" = $tenantDatabase.ServerName
        "DatabaseName" = $tenantDatabase.DatabaseName
        "ServiceObjective" = $tenantDatabase.ServiceObjective
        "ElasticPoolName" = $tenantDatabase.ElasticPoolName
      }

      # Add operation object to queue for tracking later
      $operationId = $operationObject.Id
      if (!$operationQueueMap.ContainsKey("$operationId"))
      {
        $operationQueue += $operationObject
        $operationQueueMap.Add("$operationId", $databaseDetails)      
      }
    }  
  }  
  else 
  {
    # There are no more databases eligible for recovery     
    break
  }
}

# Check on status of database recovery operations 
while ($operationQueue.Count -gt 0)
{
  foreach($recoveryJob in $operationQueue)
  {
    # Monitor the status of previous ongoing deployments
    if ($recoveryJob.GetType().Name -eq 'PSCustomObject')
    {
      $operationDetails = Get-AzureRmLog -CorrelationId $recoveryJob.Id 3>$null

      if ($operationDetails.Status.Value -contains "Succeeded")
      {
        # Start new restore operation if there are any databases left to recover
        $tenantListPerPool = Select-HighestPriorityUnrecoveredTenantPerPool -Catalog $tenantCatalog
        if ($tenantListPerPool.Count -gt 0)
        {
          $selectedPool = $tenantListPerPool.Keys | Select-Object -First 1  
          $tenantDatabase = $tenantListPerPool[$selectedPool]

          # Update tenant database recovery state
          $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startRecovery" -ServerName $tenantDatabase.ServerName -DatabaseName $tenantdatabase.DatabaseName

          $operationObject = Start-AsynchronousDatabaseRecovery -AzureContext $azureContext -TenantDatabase $tenantDatabase
          $databaseDetails = @{
            "ServerName" = $tenantDatabase.ServerName
            "DatabaseName" = $tenantDatabase.DatabaseName
            "ServiceObjective" = $tenantDatabase.ServiceObjective
            "ElasticPoolName" = $tenantDatabase.ElasticPoolName
          }

          # Add operation object to queue for tracking later
          $operationId = $operationObject.Id
          if (!$operationQueueMap.ContainsKey("$operationId"))
          {
            $operationQueue += $operationObject
            $operationQueueMap.Add("$operationId", $databaseDetails) 
          }
        }

        # Update tenant database recovery state
        Complete-AsynchronousDatabaseRecovery -RecoveryJobId $recoveryJob.Id 

        # Remove completed job from queue for polling
        $operationQueue = $operationQueue -ne $recoveryJob      

        # Output recovery progress 
        $recoveredDatabaseCount+= 1
        $DatabaseRecoveryPercentage = [math]::Round($recoveredDatabaseCount/$tenantDatabaseCount,2)
        $DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
        Write-Output "$DatabaseRecoveryPercentage% ($($recoveredDatabaseCount) of $tenantDatabaseCount)"  
      }
      elseif ($operationDetails.Status.Value -In 'Failed', 'Canceled')
      {
        # Mark errorState for databases that have not been recovered 
        $databaseDetails = $operationQueueMap[$recoveryJob.Id]
        $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "markError" -ServerName $databaseDetails.ServerName -DatabaseName $databaseDetails.DatabaseName
      
        # Remove completed job from queue for polling
        $operationQueue = $operationQueue -ne $recoveryJob
      }      
    }
    elseif (($recoveryJob.IsCompleted) -and ($recoveryJob.Status -eq 'RanToCompletion'))
    {
      # Start new restore operation if there are any databases left to recover
      $tenantListPerPool = Select-HighestPriorityUnrecoveredTenantPerPool -Catalog $tenantCatalog
      if ($tenantListPerPool.Count -gt 0)
      {
        $selectedPool = $tenantListPerPool.Keys | Select-Object -First 1  
        $tenantDatabase = $tenantListPerPool[$selectedPool]

        # Update tenant database recovery state
        $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startRecovery" -ServerName $tenantDatabase.ServerName -DatabaseName $tenantdatabase.DatabaseName

        $operationObject = Start-AsynchronousDatabaseRecovery -AzureContext $azureContext -TenantDatabase $tenantDatabase
        $databaseDetails = @{
          "ServerName" = $tenantDatabase.ServerName
          "DatabaseName" = $tenantDatabase.DatabaseName
          "ServiceObjective" = $tenantDatabase.ServiceObjective
          "ElasticPoolName" = $tenantDatabase.ElasticPoolName
        }

        # Add operation object to queue for tracking later
        $operationId = $operationObject.Id
        if (!$operationQueueMap.ContainsKey("$operationId"))
        {
          $operationQueue += $operationObject
          $operationQueueMap.Add("$operationId", $databaseDetails) 
        }
      }

      # Update tenant database recovery state
      Complete-AsynchronousDatabaseRecovery -RecoveryJobId $recoveryJob.Id 

      # Remove completed job from queue for polling
      $operationQueue = $operationQueue -ne $recoveryJob      

      # Output recovery progress 
      $recoveredDatabaseCount+= 1
      $DatabaseRecoveryPercentage = [math]::Round($recoveredDatabaseCount/$tenantDatabaseCount,2)
      $DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
      Write-Output "$DatabaseRecoveryPercentage% ($($recoveredDatabaseCount) of $tenantDatabaseCount)"               
    }
    elseif (($recoveryJob.IsCompleted) -and ($recoveryJob.Status -eq "Faulted"))
    {
      # Mark errorState for databases that have not been recovered 
      $databaseDetails = $operationQueueMap[$recoveryJob.Id]
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "markError" -ServerName $databaseDetails.ServerName -DatabaseName $databaseDetails.DatabaseName
      
      # Remove completed job from queue for polling
      $operationQueue = $operationQueue -ne $recoveryJob
    }
  }
}

# Output recovery progress 
$DatabaseRecoveryPercentage = [math]::Round($recoveredDatabaseCount/$tenantDatabaseCount,2)
$DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
Write-Output "$DatabaseRecoveryPercentage% ($($recoveredDatabaseCount) of $tenantDatabaseCount)"
