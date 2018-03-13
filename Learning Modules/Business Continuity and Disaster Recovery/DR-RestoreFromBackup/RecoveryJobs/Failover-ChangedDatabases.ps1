<#
.SYNOPSIS
  Failover tenant databases that have been replicated to the original region.

.DESCRIPTION
  This script is intended to be run as a background job in the 'Repatriate-IntoOriginalRegion' script that repatriates the Wingtip SaaS app environment (apps, databases, servers e.t.c) into the origin.
  The script fails over tenant databases that have previously been geo-replicates into the original Wingtip region

.PARAMETER WingtipRecoveryResourceGroup
  Resource group in the recovery region that contains recovered resources

.PARAMETER MaxConcurrentFailoverOperations
  Maximum number of failover operations that can be run concurrently

.EXAMPLE
  [PS] C:\>.\Failover-ChangedTenantDatabases.ps1 -WingtipRecoveryResourceGroup "sampleRecoveryResourceGroup"
#>
[cmdletbinding()]
param (
  [parameter(Mandatory=$true)]
  [String] $WingtipRecoveryResourceGroup,

  [parameter(Mandatory=$false)]
  [int] $MaxConcurrentFailoverOperations=50 
)

Import-Module "$using:scriptPath\..\..\Common\CatalogAndDatabaseManagement" -Force
Import-Module "$using:scriptPath\..\..\Common\AzureSqlAsyncManagement" -Force
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


# Get the tenant catalog in the recovery region
$tenantCatalog = Get-Catalog -ResourceGroupName $WingtipRecoveryResourceGroup -WtpUser $wtpUser.Name

# Initialize replication variables
$sleepInterval = 10
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
  $taskObject = Invoke-AzureSQLDatabaseFailoverAsync `
                  -AzureContext $AzureContext `
                  -ResourceGroupName $wtpUser.ResourceGroupName `
                  -ServerName $SecondaryTenantServerName `
                  -DatabaseName $TenantDatabaseName `
                  -ReplicationLinkId "$($replicationObject.LinkId)"  
   
  return $taskObject
}

<#
 .SYNOPSIS  
  Marks the failover for a tenant database as complete after failover is concluded
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

    # Update tenant database recovery state
    $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "conclude" -ServerName $restoredServerName -DatabaseName $databaseDetails.DatabaseName
    if (!$dbState)
    {
      Write-Verbose "Could not update recovery state for database: '$restoredServerName/$($databaseDetails.DatabaseName)'"
    }
  }
  else
  {
    Write-Verbose "Could not find database details for recovery job with Id: '$FailoverJobId'"
  }
}

#----------------------------Main script--------------------------------------------------
$failoverQueue = @()
$tenantList = Get-ExtendedTenant -Catalog $tenantCatalog
$tenantDatabaseList = Get-ExtendedDatabase -Catalog
$replicatedDatabaseList = $tenantDatabaseList | Where-Object{$_.RecoveryState -eq 'replicated'}

# Add replicated databases to queue of tenant databases that will be failed over
foreach ($database in $replicatedDatabaseList)
{
  $dbProperties = @{
    "ServerName" = $database.ServerName
    "DatabaseName" = $database.DatabaseName
  }
  $failoverQueue += $dbProperties
}

# Add tenant databases that have been changed in the recovery region to queue of databases that will be failed over
foreach ($tenant in $tenantList)
{
  $tenantDataChanged = Test-IfTenantDataChanged -Catalog $tenantCatalog -TenantName $tenant.TenantName
  $tenantServerName = $tenant.ServerName.split('.')[0]
  $tenantDatabaseObject = $tenantDatabaseList | Where-Object{(($_.ServerName -eq $tenantServerName) -and ($_.DatabaseName -eq $tenant.DatabaseName))}

  if ($tenantDataChanged -and ($tenantDatabaseObject.RecoveryState -ne 'complete') -and ($tenantDatabaseObject -NotIn $failoverQueue))
  {
    $dbProperties = @{
      "ServerName" = $tenantDatabaseObject.ServerName
      "DatabaseName" = $tenantDatabaseObject.DatabaseName
    }
    $failoverQueue += $dbProperties
  }
}
$replicatedDatabaseCount = $failoverQueue.Count

while(($failoverQueue.Count -gt 0) -or ($operationQueue.Count -gt 0))
{
  # Get database recovery status
  $tenantDatabaseList = Get-ExtendedDatabase -Catalog $tenantCatalog | Where-Object{(($_.ServerName -In $failoverQueue.ServerName) -and ($_.DatabaseName -In $failoverQueue.DatabaseName))}

  # Issue asynchronous call to failover eligible databases
  foreach ($database in $tenantDatabaseList)
  {
    if ($database.RecoveryState -eq 'replicated')
    {
      # Remove database from failover queue
      $dbProperties = @{
        "ServerName" = $database.ServerName
        "DatabaseName" = $database.DatabaseName
      }
      $failoverQueue = $failoverQueue -ne $dbProperties
      $originServerName = ($database.ServerName -split "$($config.RecoveryRoleSuffix)")[0]

      # Update database recovery state
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startFailback" -ServerName $database.ServerName -DatabaseName $database.DatabaseName

      # Issue asynchronous call to failover databases
      $operationObject = Start-AsynchronousDatabaseFailover -AzureContext $azureContext -SecondaryTenantServerName $originServerName -TenantDatabaseName $database.DatabaseName

      # Add operation to queue for tracking
      $operationId = $operationObject.Id
      if (!$operationQueueMap.ContainsKey("$operationId"))
      {
        $operationQueue += $operationObject
        $operationQueueMap.Add("$operationId", $dbProperties)
      } 
    }
  }

  # Check on status of failover operations 
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
      $databaseDetails = $operationQueueMap[$failoverJob.Id]
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "markError" -ServerName $databaseDetails.ServerName -DatabaseName $databaseDetails.DatabaseName
      
      # Remove completed job from queue for polling
      $operationQueue = $operationQueue -ne $failoverJob
    }
  }
}

# Output recovery progress 
$DatabaseRecoveryPercentage = [math]::Round($failoverCount/$replicatedDatabaseCount,2)
$DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
Write-Output "$DatabaseRecoveryPercentage% ($($failoverCount) of $replicatedDatabaseCount)"

