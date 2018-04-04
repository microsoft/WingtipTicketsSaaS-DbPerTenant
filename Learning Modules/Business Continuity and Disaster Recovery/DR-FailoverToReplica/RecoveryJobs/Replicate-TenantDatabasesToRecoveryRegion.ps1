<#
.SYNOPSIS
  Replicates tenant databases to a recovery region.

.DESCRIPTION
  This script is intended to be run as a background job in the 'Deploy-WingtipTicketsReplica' script that replicates the Wingtip SaaS app (apps, databases, servers e.t.c) into a recovery region.
  The script geo-replicates tenant databases into a recovery region

.PARAMETER WingtipRecoveryResourceGroup
  Resource group in the recovery region that contains recovered resources

.PARAMETER MaxConcurrentReplicationOperations
  Maximum number of replication operations that can be run concurrently

.EXAMPLE
  [PS] C:\>.\Replicate-TenantDatabasesToRecoveryRegion.ps1 -WingtipRecoveryResourceGroup "sampleRecoveryResourceGroup"
#>
[cmdletbinding()]
param (
  [parameter(Mandatory=$true)]
  [String] $WingtipRecoveryResourceGroup,

  [parameter(Mandatory=$false)]
  [int] $MaxConcurrentReplicationOperations=50 
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
$sleepInterval = 10
$currentSubscriptionId = Get-SubscriptionId

# Get the tenant catalog in the recovery region
$tenantCatalog = Get-Catalog -ResourceGroupName $WingtipRecoveryResourceGroup -WtpUser $wtpUser.Name

# Initialize replication variables
$replicationQueue = @()
$operationQueue = @()
$operationQueueMap = @{}
$replicatedDatabaseCount = 0

#---------------------- Helper Functions --------------------------------------------------------------
<#
 .SYNOPSIS  
  Starts an asynchronous call to create a readable secondary replica of a tenant database in the recovery region
  This function returns a task object that can be used to track the status of the operation
#>
function Start-AsynchronousDatabaseReplication
{
  param
  (
    [Parameter(Mandatory=$true)]
    [Microsoft.Azure.Management.Sql.Fluent.SqlManager]$AzureContext,

    [Parameter(Mandatory=$true)]
    [object]$TenantDatabase       
  )

  # Construct replication parameters
  $recoveryServerName = $TenantDatabase.ServerName + $config.RecoveryRoleSuffix
  $recoveryServer = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceNameEquals $recoveryServerName
  $databaseId = "/subscriptions/$currentSubscriptionId/resourceGroups/$($wtpUser.ResourceGroupName)/providers/Microsoft.Sql/servers/$($TenantDatabase.ServerName)/databases/$($TenantDatabase.DatabaseName)"

  # Delete any existing tenant database in the recovery location
  Remove-AzureRmSqlDatabase -ResourceGroupName $WingtipRecoveryResourceGroup -ServerName $recoveryServerName -DatabaseName $TenantDatabase.DatabaseName -ErrorAction SilentlyContinue >$null

  # Issue asynchronous replication operation
  if ($TenantDatabase.ServiceObjective -eq 'ElasticPool')
  {
    # Replicate tenant database into an elastic pool
    $taskObject = New-AzureSQLDatabaseReplicaAsync `
                    -AzureContext $AzureContext `
                    -ResourceGroupName $WingtipRecoveryResourceGroup `
                    -Location $recoveryServer.Location `
                    -ServerName $recoveryServerName `
                    -DatabaseName $TenantDatabase.DatabaseName `
                    -SourceDatabaseId $databaseId `
                    -ElasticPoolName $TenantDatabase.ElasticPoolName
  }
  else
  {
    # Replicate tenant database into a standalone database
    $taskObject = New-AzureSQLDatabaseReplicaAsync `
                    -AzureContext $AzureContext `
                    -ResourceGroupName $WingtipRecoveryResourceGroup `
                    -Location $recoveryServer.Location `
                    -ServerName $recoveryServerName `
                    -DatabaseName $TenantDatabase.DatabaseName `
                    -SourceDatabaseId $databaseId `
                    -RequestedServiceObjectiveName $TenantDatabase.ServiceObjective
  }  
  return $taskObject
}


#----------------------------Main script--------------------------------------------------

# Wait until all elastic pools have been replicated to start replicating databases
# This ensures that all required container resources have been acquired before database replication begins 
$tenantPools = Get-ExtendedElasticPool -Catalog $tenantCatalog | Where-Object {$_.ServerName -notmatch "$($config.RecoveryRoleSuffix)$"} 
$poolCount = @($tenantPools).Count
$replicatedElasticPools = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers/elasticpools"

while (@($replicatedElasticPools).Count -lt $poolCount)
{
  Start-Sleep $sleepInterval
  $replicatedElasticPools = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers/elasticpools"
  Write-Output "waiting for pool(s) to complete deployment ..."
}

# Find previous replication operations that are not yet complete. 
# This allows the script to be re-run if an error occurs during replication
$ongoingDeployments = @()  
$operationsLog = Get-AzureRmLog -ResourceGroupName $WingtipRecoveryResourceGroup -StartTime (Get-Date).AddDays(-1) -MaxRecord 200 3>$null | Where-Object {($_.OperationName.Value -eq 'Microsoft.Sql/servers/databases/write')}
$operationsLog = $operationsLog | Group-Object -Property 'CorrelationId'

# Find all ongoing database recovery operations
foreach ($operationSequence in $operationsLog)
{
  if ($operationSequence.Group.EventName.Value -notcontains "EndRequest")
  {
    $operation = $operationSequence.Group | Where-Object {$_.EventName.Value -eq "BeginRequest"}
    $ongoingDeployments += $operation
  }
}

# Add ongoing deployments to queue of background jobs that will be monitored
if ($ongoingDeployments.Count -gt 0)
{
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
  
# Get all tenant databases that have replicated into the recovery region 
$replicatedDatabaseInstances = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers/databases" -ResourceNameContains "tenants"

# Get list of tenant databases to be replicated
$tenantDatabaseList = Get-ExtendedDatabase -Catalog $tenantCatalog | Where-Object{$_.ServerName -notmatch "$($config.RecoveryRoleSuffix)$"}
$tenantDatabaseCount = $tenantDatabaseList.Count
foreach ($database in $tenantDatabaseList)
{
  $currTenantServerName = $database.ServerName
  $originTenantServerName = ($currTenantServerName -split "$($config.RecoveryRoleSuffix)$")[0]
  $recoveryTenantServerName = $originTenantServerName + $config.RecoveryRoleSuffix

  $replicationLink = Get-AzureRmSqlDatabaseReplicationLink `
                      -ResourceGroupName $WingtipRecoveryResourceGroup `
                      -ServerName $recoveryTenantServerName `
                      -DatabaseName $database.DatabaseName `
                      -PartnerResourceGroupName $wtpUser.ResourceGroupName `
                      -PartnerServerName $originTenantServerName `
                      -ErrorAction SilentlyContinue

  if (!$replicationLink)
  {
    $dbProperties = Get-ExtendedDatabase -Catalog $tenantCatalog -ServerName $currTenantServerName -DatabaseName $database.DatabaseName
    $replicationQueue += $dbProperties
  }
  else
  {
    $replicatedDatabaseCount += 1
  }  
}

# Output recovery progress
$DatabaseRecoveryPercentage = [math]::Round($replicatedDatabaseCount/$tenantDatabaseCount,2)
$DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
Write-Output "Replicating ... ($($replicatedDatabaseCount) of $tenantDatabaseCount complete)"

# Issue a request to replicate databases asynchronously till concurrent operation limit is reached
$azureContext = Get-RestAPIContext
while ($operationQueue.Count -le $MaxConcurrentReplicationOperations)
{
  $currentDatabase = $replicationQueue[0]
  if ($currentDatabase)
  {
    $replicationQueue = $replicationQueue -ne $currentDatabase
    $operationObject = Start-AsynchronousDatabaseReplication -AzureContext $azureContext -TenantDatabase $currentDatabase
    $databaseDetails = @{
      "ServerName" = $currentDatabase.ServerName
      "DatabaseName" = $currentDatabase.DatabaseName
      "ServiceObjective" = $currentDatabase.ServiceObjective
      "ElasticPoolName" = $currentDatabase.ElasticPoolName
    }

    # Add operation to queue for tracking
    $operationId = $operationObject.Id
    if (!$operationQueueMap.ContainsKey("$operationId"))
    {
      $operationQueue += $operationObject
      $operationQueueMap.Add("$operationId", $databaseDetails)
    }      
  }
  else 
  {
    # There are no more databases eligible for replication     
    break
  }
}

# Check on status of database replication operations
while ($operationQueue.Count -gt 0)
{
  foreach($replicationJob in $operationQueue)
  {
    if (($replicationJob.IsCompleted) -and ($replicationJob.Status -eq 'RanToCompletion'))
    {
      # Start new replication operation if there are any databases left to replicate
      $currentDatabase = $replicationQueue[0]
      if ($currentDatabase)
      {
        $replicationQueue = $replicationQueue -ne $currentDatabase
        $operationObject = Start-AsynchronousDatabaseReplication -AzureContext $azureContext -TenantDatabase $currentDatabase
        $databaseDetails = @{
          "ServerName" = $currentDatabase.ServerName
          "DatabaseName" = $currentDatabase.DatabaseName
          "ServiceObjective" = $currentDatabase.ServiceObjective
          "ElasticPoolName" = $currentDatabase.ElasticPoolName
        }

        # Add operation to queue for tracking
        $operationId = $operationObject.Id
        if (!$operationQueueMap.ContainsKey("$operationId"))
        {
          $operationQueue += $operationObject
          $operationQueueMap.Add("$operationId", $databaseDetails)
        }      
      }

      # Remove completed job from queue for polling
      $operationQueue = $operationQueue -ne $replicationJob  
      $replicatedDatabaseCount+= 1    

      # Output recovery progress 
      $DatabaseRecoveryPercentage = [math]::Round($replicatedDatabaseCount/$tenantDatabaseCount,2)
      $DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
      Write-Output "Replicating ... ($($replicatedDatabaseCount) of $tenantDatabaseCount complete)"               
    }
    elseif (($replicationJob.IsCompleted) -and ($replicationJob.Status -eq "Faulted"))
    {
      # Remove completed job from queue for polling
      $operationQueue = $operationQueue -ne $replicationJob
      $jobId = $replicationJob.Id
      $databaseDetails = $operationQueueMap["$jobId"]

      Write-Verbose "Could not replicate database: '$($databaseDetails.ServerName)/$($databaseDetails.DatabaseName)'"      
    }
  }
}

# Output replication progress
$DatabaseRecoveryPercentage = [math]::Round($replicatedDatabaseCount/$tenantDatabaseCount,2)
$DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
Write-Output "Replicated ($($replicatedDatabaseCount) of $tenantDatabaseCount)"
