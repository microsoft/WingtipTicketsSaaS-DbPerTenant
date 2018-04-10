<#
.SYNOPSIS
  Failover tenant databases that have been replicated to the original region.

.DESCRIPTION
  This script is intended to be run as a background job in the 'Repatriate-IntoOriginalRegion' script that repatriates the Wingtip SaaS app environment (apps, databases, servers e.t.c) into the origin.
  The script fails over tenant databases that have previously been geo-replicates into the original Wingtip region

.PARAMETER WingtipRecoveryResourceGroup
  Resource group in the recovery region that contains recovered resources

.EXAMPLE
  [PS] C:\>.\Failover-TenantDatabasesToOriginalRegion.ps1 -WingtipRecoveryResourceGroup "sampleRecoveryResourceGroup"
#>
[cmdletbinding()]
param (
  [parameter(Mandatory=$true)]
  [String] $WingtipRecoveryResourceGroup
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
$wtpUser = Get-UserConfig
$config = Get-Configuration

# Get the tenant catalog in the recovery region
$tenantCatalog = Get-Catalog -ResourceGroupName $WingtipRecoveryResourceGroup -WtpUser $wtpUser.Name

# Initialize replication variables
$operationQueue = @()
$operationQueueMap = @{}
$failoverCount = 0

#---------------------- Helper Functions --------------------------------------------------------------
<#
 .SYNOPSIS  
  Starts an asynchronous call to failover a tenant database to the origin region
  This function returns a task object that can be used to track the status of the operation
#>
function Start-AsynchronousDatabaseFailover
{
  param
  (
    [Parameter(Mandatory=$true)]
    [Microsoft.Azure.Management.Sql.Fluent.SqlManager]$AzureContext,

    [Parameter(Mandatory=$true)]
    [String]$SecondaryTenantServerName,

    [Parameter(Mandatory=$true)]
    [String]$TenantDatabaseName
  )

  # Get replication link Id
  $replicationObject = Get-AzureRmSqlDatabaseReplicationLink `
                          -ResourceGroupName $wtpUser.ResourceGroupName `
                          -ServerName $SecondaryTenantServerName `
                          -DatabaseName $TenantDatabaseName `
                          -PartnerResourceGroupName $WingtipRecoveryResourceGroup

  # Issue asynchronous failover operation
  if ($replicationObject)
  {    
    $taskObject = Invoke-AzureSQLDatabaseFailoverAsync `
                    -AzureContext $AzureContext `
                    -ResourceGroupName $wtpUser.ResourceGroupName `
                    -ServerName $SecondaryTenantServerName `
                    -DatabaseName $TenantDatabaseName `
                    -ReplicationLinkId "$($replicationObject.LinkId)"  
     
    return $taskObject
  }
  else
  {
    return $null
  }
}

<#
 .SYNOPSIS  
  Marks the failover for a tenant database as complete and updates tenant shard after failover is concluded
#>
function Complete-AsynchronousDatabaseFailover
{
  param
  (
    [Parameter(Mandatory=$true)]
    [String]$FailoverJobId
  )

  $databaseDetails = $operationQueueMap[$FailoverJobId]
  if ($databaseDetails)
  {
    $restoredServerName = $databaseDetails.ServerName
    $originServerName = ($restoredServerName -split "$($config.RecoveryRoleSuffix)")[0]

    # Update tenant shard to origin
    $shardUpdate = Update-TenantShardInfo -Catalog $tenantCatalog -TenantName $databaseDetails.DatabaseName -FullyQualifiedTenantServerName "$originServerName.database.windows.net" -TenantDatabaseName $databaseDetails.DatabaseName
    if ($shardUpdate)
    {
      # Update recovery state of tenant resources
      $tenantDatabaseObject = Get-ExtendedDatabase -Catalog $tenantCatalog -ServerName $restoredServerName -DatabaseName $databaseDetails.DatabaseName
      $serverState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "conclude" -ServerName $restoredServerName
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "conclude" -ServerName $restoredServerName -DatabaseName $databaseDetails.DatabaseName
      if ($tenantDatabaseObject.ElasticPoolName)
      {
        $poolState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "conclude" -ServerName $restoredServerName -ElasticPoolName $tenantDatabaseObject.ElasticPoolName
      }

      if (!$dbState)
      {
        Write-Verbose "Could not update recovery state for database: '$restoredServerName/$($databaseDetails.DatabaseName)'"
      } 
    }
    else
    {
        Write-Verbose "Could not update tenant shard to point to origin: '$restoredServerName/$($databaseDetails.DatabaseName)'"
    }   
  }
  else
  {
    Write-Verbose "Could not find database details for recovery job with Id: '$FailoverJobId'"
  }
}

#----------------------------Main script--------------------------------------------------

# Get list of databases that were added in the recovery region
$databaseList = Get-ExtendedDatabase -Catalog $tenantCatalog
$recoveryDatabaseList = $databaseList | Where-Object{$_.ServerName -match "$($config.RecoveryRoleSuffix)$"}
$originDatabaseList = $databaseList | Where-Object{$_.ServerName -notmatch "$($config.RecoveryRoleSuffix)$"}
$failoverQueue = @()
$replicatingDatabases = @()

# Add databases to failover queue (if applicable)
foreach ($database in $recoveryDatabaseList)
{
  $originServerName = ($database.ServerName -split "$($config.RecoveryRoleSuffix)$")[0]
  $originDatabase = $originDatabaseList | Where-Object {($_.DatabaseName -eq $database.DatabaseName) -and ($_.ServerName -eq $originServerName)}

  if ($database.RecoveryState -ne 'complete')
  {
    if (!$originDatabase)
    {
      $replicatingDatabases += $database
      $failoverQueue += $database
    }
    else
    {
      # Get replication status of tenant database in origin region
      $replicationLink = Get-AzureRmSqlDatabaseReplicationLink `
                            -ResourceGroupName $wtpUser.ResourceGroupName `
                            -ServerName $originServerName `
                            -DatabaseName $database.DatabaseName `
                            -PartnerResourceGroupName $WingtipRecoveryResourceGroup `
                            -PartnerServerName $database.ServerName `
                            -ErrorAction SilentlyContinue

      if ($replicationLink.Role -eq 'Secondary')
      {
        $failoverQueue += $database
      }
      else
      {
        # Mark database recovery state as complete
        $failoverCount += 1
        $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startFailback" -ServerName $database.ServerName -DatabaseName $database.DatabaseName
        $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "conclude" -ServerName $database.ServerName -DatabaseName $database.DatabaseName
      }
    }
  }  
}

$replicatedDatabaseCount = $failoverQueue.Count + $failoverCount

if ($replicatedDatabaseCount -eq 0)
{
  Write-Output "100% (0 of 0)"
  exit
}
elseif ($replicatedDatabaseCount -eq $failoverCount)
{
  Write-Output "100% ($failoverCount of $replicatedDatabaseCount)"
  exit
}

# Wait for all databases to have replicas before failover
$allReplicasCreated = $false
while (!$allReplicasCreated)
{
  foreach ($database in $failoverQueue)
  {
    $currServerName = $database.ServerName
    $originServerName = ($currServerName -split "$($config.RecoveryRoleSuffix)$")[0]
    $recoveryServerName = $originServerName + $config.RecoveryRoleSuffix

    # Get replication status of tenant database in recovery region
    $replicationLink = Get-AzureRmSqlDatabaseReplicationLink `
                          -ResourceGroupName $WingtipRecoveryResourceGroup `
                          -ServerName $recoveryServerName `
                          -DatabaseName $database.DatabaseName `
                          -PartnerResourceGroupName $wtpUser.ResourceGroupName `
                          -PartnerServerName $originServerName `
                          -ErrorAction SilentlyContinue
    if (!$replicationLink)
    {
      $allReplicasCreated = $false
      break
    }
    
    $allReplicasCreated = $true      
  }
  Write-Output "waiting for database replicas to be created ..." 
}

# Output recovery progress
$DatabaseRecoveryPercentage = [math]::Round($failoverCount/$replicatedDatabaseCount,2)
$DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
Write-Output "$DatabaseRecoveryPercentage% ($($failoverCount) of $replicatedDatabaseCount)"

# Issue a request to failover tenant databases asynchronously
$azureContext = Get-RestAPIContext
while ($true)
{
  # Issue asynchronous call to failover eligible databases
  if ($failoverQueue.Count -gt 0)
  {
    $currentDatabase = $failoverQueue[0]

    $dbProperties = @{
    "ServerName" = $currentDatabase.ServerName
    "DatabaseName" = $currentDatabase.DatabaseName
    }
    $failoverQueue = $failoverQueue -ne $currentDatabase
    $originServerName = ($currentDatabase.ServerName -split "$($config.RecoveryRoleSuffix)")[0]   

    # Issue asynchronous call to failover databases
    $operationObject = Start-AsynchronousDatabaseFailover -AzureContext $azureContext -SecondaryTenantServerName $originServerName -TenantDatabaseName $currentDatabase.DatabaseName

    if ($operationObject.Exception)
    {
      Write-Verbose $operationObject.Exception.InnerException

      # Mark database failover error
      # Note: To make this process more robust, you would likely check the HTTP status code that is returned and respond appropriately. For example, if a 429 | too many requests is received, you will want to pause for the appropriate amount of time
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "markError" -ServerName $currentDatabase.ServerName -DatabaseName $currentDatabase.DatabaseName

      # Retry failover if unsuccessful
      $failoverQueue = @($currentDatabase) + $failoverQueue
      Start-Sleep 10
    }
    elseif (!$operationObject)
    {
      # Retry failover if unsuccessful
      $failoverQueue = @($currentDatabase) + $failoverQueue
      Start-Sleep 10
    }
    else
    { 
      # Update recovery state of tenant resources
      $serverState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startFailback" -ServerName $currentDatabase.ServerName
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startFailback" -ServerName $currentDatabase.ServerName -DatabaseName $currentDatabase.DatabaseName
      $poolState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startFailback" -ServerName $currentDatabase.ServerName -ElasticPoolName $currentDatabase.ElasticPoolName

      # Add operation to queue for tracking
      $operationId = $operationObject.Id
      if (!$operationQueueMap.ContainsKey("$operationId"))
      {
        $operationQueue += $operationObject
        $operationQueueMap.Add("$operationId", $dbProperties)
      }  
    } 
  }
  else
  {
    # There are no more databases eligible for failover     
    break
  }  
}

# Check on status of database failover operations
while ($operationQueue.Count -gt 0)
{
  foreach($failoverJob in $operationQueue)
  {
    if (($failoverJob.IsCompleted) -and ($failoverJob.Status -eq 'RanToCompletion'))
    {
      # Update tenant database recovery state
      Complete-AsynchronousDatabaseFailover -FailoverJobId $failoverJob.Id 

      # Remove completed job from queue for polling
      $operationQueue = $operationQueue -ne $failoverJob      

      # Output recovery progress 
      $failoverCount+= 1
      $DatabaseRecoveryPercentage = [math]::Round($failoverCount/$replicatedDatabaseCount,2)
      $DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
      Write-Output "$DatabaseRecoveryPercentage% ($($failoverCount) of $replicatedDatabaseCount)"               
    }
    elseif (($failoverJob.IsCompleted) -and ($failoverJob.Status -eq "Faulted"))
    {
      # Mark errorState for databases that could not failover
      $jobId = $failoverJob.Id
      $databaseDetails = $operationQueueMap["$jobId"]
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "markError" -ServerName $databaseDetails.ServerName -DatabaseName $databaseDetails.DatabaseName
        
      # Remove completed job from queue for polling
      $operationQueue = $operationQueue -ne $failoverJob

      # Retry failover for database
      $originServerName = ($databaseDetails.ServerName -split "$($config.RecoveryRoleSuffix)$")[0]
      $operationObject = Start-AsynchronousDatabaseFailover -AzureContext $azureContext -SecondaryTenantServerName $originServerName -TenantDatabaseName $databaseDetails.DatabaseName

      # Update recovery state of tenant resources
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startFailback" -ServerName $databaseDetails.ServerName -DatabaseName $databaseDetails.DatabaseName

      # Add operation to queue for tracking
      $operationId = $operationObject.Id
      $dbProperties = @{
        "ServerName" = $databaseDetails.ServerName
        "DatabaseName" = $databaseDetails.DatabaseName
      }
      if (!$operationQueueMap.ContainsKey("$operationId"))
      {
        $operationQueue += $operationObject
        $operationQueueMap.Add("$operationId", $dbProperties)
      } 
    }
  }
}

# Output recovery progress 
$DatabaseRecoveryPercentage = [math]::Round($failoverCount/$replicatedDatabaseCount,2)
$DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
Write-Output "$DatabaseRecoveryPercentage% ($($failoverCount) of $replicatedDatabaseCount)"
