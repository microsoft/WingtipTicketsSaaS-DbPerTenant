<#
.SYNOPSIS
  Failover tenant databases into recovery region

.DESCRIPTION
  This script is intended to be run as a background job in the 'Failover-IntoRecoveryRegion' script that fails over the Wingtip SaaS app into a recovery region.
  The script uses the geo-replication capability of Azure SQL databases to failover tenant databases.

.PARAMETER WingtipRecoveryResourceGroup
  Resource group that will be used to contain recovered resources

.EXAMPLE
  [PS] C:\>.\Failover-TenantDatabasesToRecoveryRegion.ps1 -WingtipRecoveryResourceGroup "sampleResourceRecoveryGroup"
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
                          -ResourceGroupName $WingtipRecoveryResourceGroup `
                          -ServerName $SecondaryTenantServerName `
                          -DatabaseName $TenantDatabaseName `
                          -PartnerResourceGroupName $wtpUser.ResourceGroupName

  # Issue asynchronous failover operation
  if ($replicationObject)
  {
    $taskObject = Invoke-AzureSQLDatabaseFailoverAsync `
                    -AzureContext $AzureContext `
                    -ResourceGroupName $WingtipRecoveryResourceGroup `
                    -ServerName $SecondaryTenantServerName `
                    -DatabaseName $TenantDatabaseName `
                    -ReplicationLinkId "$($replicationObject.LinkId)" `
                    -AllowDataLoss
     
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
    $originServerName = $databaseDetails.ServerName
    $restoredServerName = $originServerName + $config.RecoveryRoleSuffix

    # Update tenant shard to recovery region
    $shardUpdate = Update-TenantShardInfo -Catalog $tenantCatalog -TenantName $databaseDetails.DatabaseName -FullyQualifiedTenantServerName "$restoredServerName.database.windows.net" -TenantDatabaseName $databaseDetails.DatabaseName
    if ($shardUpdate)
    {
      # Update recovery state of tenant resources
      $tenantDatabaseObject = Get-ExtendedDatabase -Catalog $tenantCatalog -ServerName $originServerName -DatabaseName $databaseDetails.DatabaseName
      $serverState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endFailover" -ServerName $originServerName
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endFailover" -ServerName $originServerName -DatabaseName $databaseDetails.DatabaseName
      if ($tenantDatabaseObject.ElasticPoolName)
      {
        $poolState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endFailover" -ServerName $originServerName -ElasticPoolName $tenantDatabaseObject.ElasticPoolName
      }

      if (!$dbState)
      {
        Write-Verbose "Could not update recovery state for database: '$originServerName/$($databaseDetails.DatabaseName)'"
      } 
    }
    else
    {
      Write-Verbose "Could not update tenant shard to point to recovery: '$restoredServerName/$($databaseDetails.DatabaseName)'"
    }   
  }
  else
  {
    Write-Verbose "Could not find database details for recovery job with Id: '$FailoverJobId'"
  }
}

#----------------------------Main script--------------------------------------------------

# Get list of tenant databases
$databaseList = Get-ExtendedDatabase -Catalog $tenantCatalog
$originDatabaseList = $databaseList | Where-Object{$_.ServerName -notmatch "$($config.RecoveryRoleSuffix)$"}
$failoverQueue = @()

# Add eligible tenant databases to failover queue in priority order
$eligibleTenantList = Get-ExtendedTenant -Catalog $tenantCatalog -SortTenants | Where-Object{$_.TenantRecoveryState -ne 'OnlineInRecovery'}
foreach ($tenant in $eligibleTenantList)
{
  $tenantServerName = $tenant.ServerName.split('.')[0]
  $originTenantServerName = ($tenantServerName -split "$($config.RecoveryRoleSuffix)$")[0]
  $recoveryTenantServerName = $originTenantServerName + $config.RecoveryRoleSuffix
  $originDatabase = $originDatabaseList | Where-Object {($_.DatabaseName -eq $tenant.DatabaseName) -and ($_.ServerName -eq $originTenantServerName)}

  if ($originDatabase.RecoveryState -ne 'failedOver')
  {
    # Get replication status of tenant database
    $replicationLink = Get-AzureRmSqlDatabaseReplicationLink `
                        -ResourceGroupName $WingtipRecoveryResourceGroup `
                        -ServerName $recoveryTenantServerName `
                        -DatabaseName $tenant.DatabaseName `
                        -PartnerResourceGroupName $wtpUser.ResourceGroupName `
                        -PartnerServerName $originTenantServerName `
                        -ErrorAction Stop

    if (!$replicationLink)
    {
      throw "Could not find replication link for tenant database: $originTenantServerName/$($tenant.DatabaseName)"
    }
    elseif ($replicationLink.Role -eq 'Secondary')
    {
      $failoverQueue += $originDatabase
    }
    else
    {
      # Mark tenant database as failed over
      $failoverCount += 1
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endFailover" -ServerName $originTenantServerName -DatabaseName $tenant.DatabaseName      
    }
  }  
}
$replicatedDatabaseCount = $failoverQueue.Count

if ($replicatedDatabaseCount -eq 0)
{
  Write-Output "100% ($failoverCount of $replicatedDatabaseCount)"
  exit
}

# Output recovery progress
$DatabaseRecoveryPercentage = [math]::Round($failoverCount/$replicatedDatabaseCount,2)
$DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
Write-Output "$DatabaseRecoveryPercentage% ($($failoverCount) of $replicatedDatabaseCount)"

# Issue a request to failover tenant databases asynchronously
$azureContext = Get-RestAPIContext
while ($true)
{
  $currentDatabase = $failoverQueue[0]
  if ($currentDatabase)
  {
    $failoverQueue = $failoverQueue -ne $currentDatabase
    $originServerName = ($currentDatabase.ServerName -split "$($config.RecoveryRoleSuffix)$")[0]
    $recoveryServerName = $originServerName + $config.RecoveryRoleSuffix

    # Issue asynchronous failover request
    $operationObject = Start-AsynchronousDatabaseFailover -AzureContext $azureContext -SecondaryTenantServerName $recoveryServerName -TenantDatabaseName $currentDatabase.DatabaseName
    $databaseDetails = @{
      "ServerName" = $currentDatabase.ServerName
      "DatabaseName" = $currentDatabase.DatabaseName
      "ServiceObjective" = $currentDatabase.ServiceObjective
      "ElasticPoolName" = $currentDatabase.ElasticPoolName
    }

    if ($operationObject.Exception)
    {
      Write-Verbose $operationObject.Exception.InnerException

      # Mark database failover error
      # Note: To make this process more robust, you would likely check the HTTP status code that is returned and respond appropriately. For example, if a 429 | too many requests is received, you will want to pause for the appropriate amount of time
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "markError" -ServerName $currentDatabase.ServerName -DatabaseName $currentDatabase.DatabaseName
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
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startFailover" -ServerName $currentDatabase.ServerName -DatabaseName $currentDatabase.DatabaseName 

      # Add operation to queue for tracking
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
      # Remove completed job from queue for polling
      Complete-AsynchronousDatabaseFailover -FailoverJobId $failoverJob.Id
      $operationQueue = $operationQueue -ne $failoverJob  
      $failoverCount+= 1    

      # Output recovery progress 
      $DatabaseRecoveryPercentage = [math]::Round($failoverCount/$replicatedDatabaseCount,2)
      $DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
      Write-Output "$DatabaseRecoveryPercentage% ($($failoverCount) of $replicatedDatabaseCount)"               
    }
    elseif (($failoverJob.IsCompleted) -and ($failoverJob.Status -eq "Faulted"))
    {
      # Remove completed job from queue for polling
      $operationQueue = $operationQueue -ne $failoverJob
      $failoverJobId = $failoverJob.Id
      $databaseDetails = $operationQueueMap["$failoverJobId"]

      # Mark database failover error
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "markError" -ServerName $databaseDetails.ServerName -DatabaseName $databaseDetails.DatabaseName

      # Retry failover for database
      $originServerName = ($databaseDetails.ServerName -split "$($config.RecoveryRoleSuffix)$")[0]
      $recoveryServerName = $originServerName + $config.RecoveryRoleSuffix
      $operationObject = Start-AsynchronousDatabaseFailover -AzureContext $azureContext -SecondaryTenantServerName $recoveryServerName -TenantDatabaseName $databaseDetails.DatabaseName

      # Update recovery state of tenant resources
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startFailover" -ServerName $databaseDetails.ServerName -DatabaseName $databaseDetails.DatabaseName

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
