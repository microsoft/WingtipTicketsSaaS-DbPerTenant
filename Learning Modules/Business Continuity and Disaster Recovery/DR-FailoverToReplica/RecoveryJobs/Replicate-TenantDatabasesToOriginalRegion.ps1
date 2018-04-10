<#
.SYNOPSIS
  Replicates tenant databases that have been created in the recovery region into the original region.

.DESCRIPTION
  This script is intended to be run as a background job in the 'Repatriate-IntoOriginalRegion' script that repatriates the Wingtip SaaS app environment (apps, databases, servers e.t.c) into the origin.
  The script geo-replicates tenant databases tha have been changed in the recovery region into the original Wingtip region

.PARAMETER WingtipRecoveryResourceGroup
  Resource group in the recovery region that contains recovered resources

.EXAMPLE
  [PS] C:\>.\Replicate-TenantDatabasesToOriginalRegion.ps1 -WingtipRecoveryResourceGroup "sampleRecoveryResourceGroup"
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
  Starts an asynchronous call to create a readable secondary replica of a tenant database
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
  $originServerName = ($TenantDatabase.ServerName -split "$($config.RecoveryRoleSuffix)")[0]
  $originServer = Find-AzureRmResource -ResourceGroupNameEquals $wtpUser.ResourceGroupName -ResourceNameEquals $originServerName
  $databaseId = "/subscriptions/$currentSubscriptionId/resourceGroups/$WingtipRecoveryResourceGroup/providers/Microsoft.Sql/servers/$($TenantDatabase.ServerName)/databases/$($TenantDatabase.DatabaseName)"

  # Delete existing tenant database
  Remove-AzureRmSqlDatabase -ResourceGroupName $wtpUser.ResourceGroupName -ServerName $originServerName -DatabaseName $TenantDatabase.DatabaseName -ErrorAction SilentlyContinue >$null

  # Issue asynchronous replication operation
  if ($TenantDatabase.ServiceObjective -eq 'ElasticPool')
  {
    # Replicate tenant database into an elastic pool
    $taskObject = New-AzureSQLDatabaseReplicaAsync `
                    -AzureContext $AzureContext `
                    -ResourceGroupName $wtpUser.ResourceGroupName `
                    -Location $originServer.Location `
                    -ServerName $originServerName `
                    -DatabaseName $TenantDatabase.DatabaseName `
                    -SourceDatabaseId $databaseId `
                    -ElasticPoolName $TenantDatabase.ElasticPoolName
  }
  else
  {
    # Replicate tenant database into a standalone database
    $taskObject = New-AzureSQLDatabaseReplicaAsync `
                    -AzureContext $AzureContext `
                    -ResourceGroupName $wtpUser.ResourceGroupName `
                    -Location $originServer.Location `
                    -ServerName $originServerName `
                    -DatabaseName $TenantDatabase.DatabaseName `
                    -SourceDatabaseId $databaseId `
                    -RequestedServiceObjectiveName $TenantDatabase.ServiceObjective
  }  
  return $taskObject
}

<#
 .SYNOPSIS  
  Marks a tenant database replication as complete when the database has been successfully replicated
#>
function Complete-AsynchronousDatabaseReplication
{
  param
  (
    [Parameter(Mandatory=$true)]
    [String]$ReplicationJobId
  )

  $databaseDetails = $operationQueueMap[$ReplicationJobId]
  if ($databaseDetails)
  {
    $restoredServerName = $databaseDetails.ServerName

    # Update tenant database recovery state
    $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endReplication" -ServerName $restoredServerName -DatabaseName $databaseDetails.DatabaseName
    if (!$dbState)
    {
      Write-Verbose "Could not update recovery state for database: '$originServerName/$($databaseDetails.DatabaseName)'"
    }
  }
  else
  {
    Write-Verbose "Could not find database details for recovery job with Id: '$ReplicationJobId'"
  }

}

#----------------------------Main script--------------------------------------------------

# Get list of databases that were added in the recovery region
$databaseList = Get-ExtendedDatabase -Catalog $tenantCatalog
$recoveryDatabaseList = $databaseList | Where-Object{$_.ServerName -match "$($config.RecoveryRoleSuffix)$"}
$originDatabaseList = $databaseList | Where-Object{$_.ServerName -notmatch "$($config.RecoveryRoleSuffix)$"}

foreach ($database in $recoveryDatabaseList)
{
  $recoveryServerName = $database.ServerName
  $originServerName = ($recoveryServerName -split "$($config.RecoveryRoleSuffix)$")[0]
  $originDatabase = $originDatabaseList | Where-Object {($_.DatabaseName -eq $database.DatabaseName) -and ($_.ServerName -eq $originServerName)}

  # Get replication status of database
  $databaseReplicaExists = Get-AzureRmSqlDatabaseReplicationLink `
                            -ResourceGroupName $WingtipRecoveryResourceGroup `
                            -ServerName $recoveryServerName `
                            -DatabaseName $database.DatabaseName `
                            -PartnerResourceGroupName $wtpUser.ResourceGroupName `
                            -PartnerServerName $originServerName `
                            -ErrorAction SilentlyContinue

  if (!$originDatabase -and !$databaseReplicaExists)
  {
    $replicationQueue += $database
  }
  elseif ($database.RecoveryState -NotIn 'replicated', 'failedOver')
  {
    # Update database recovery state if it has completed replication
    $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endReplication" -ServerName $recoveryServerName -DatabaseName $database.DatabaseName
  }
}
$newDatabaseCount = $replicationQueue.length 

if ($newDatabaseCount -eq 0)
{
  Write-Output "100% (0 of 0)"
  exit
}
else
{
  # Output recovery progress 
  $DatabaseRecoveryPercentage = [math]::Round($replicatedDatabaseCount/$newDatabaseCount,2)
  $DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
  Write-Output "$DatabaseRecoveryPercentage% ($($replicatedDatabaseCount) of $newDatabaseCount)"

  # Issue a request to replicate changed tenant databases asynchronously
  $azureContext = Get-RestAPIContext
  while($true)
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

      if ($operationObject.Exception)
      {
        Write-Verbose $operationObject.Exception.InnerException

        # Mark database failover error
        $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "markError" -ServerName $currentDatabase.ServerName -DatabaseName $currentDatabase.DatabaseName
      }
      else
      {
        # Update database recovery state
        $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startReplication" -ServerName $currentDatabase.ServerName -DatabaseName $currentDatabase.DatabaseName

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
        # Update database recovery state
        Complete-AsynchronousDatabaseReplication -replicationJobId $replicationJob.Id 

        # Remove completed job from queue for polling
        $operationQueue = $operationQueue -ne $replicationJob      

        # Output recovery progress 
        $replicatedDatabaseCount+= 1
        $DatabaseRecoveryPercentage = [math]::Round($replicatedDatabaseCount/$newDatabaseCount,2)
        $DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
        Write-Output "$DatabaseRecoveryPercentage% ($($replicatedDatabaseCount) of $newDatabaseCount)"               
      }
      elseif (($replicationJob.IsCompleted) -and ($replicationJob.Status -eq "Faulted"))
      {
        # Mark errorState for databases that have not been replicated 
        $jobId = $replicationJob.Id
        $databaseDetails = $operationQueueMap["$jobId"]
        $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "markError" -ServerName $databaseDetails.ServerName -DatabaseName $databaseDetails.DatabaseName
        
        # Remove completed job from queue for polling
        $operationQueue = $operationQueue -ne $replicationJob
      }
    }
  }

  # Output recovery progress 
  $DatabaseRecoveryPercentage = [math]::Round($replicatedDatabaseCount/$newDatabaseCount,2)
  $DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
  Write-Output "$DatabaseRecoveryPercentage% ($($replicatedDatabaseCount) of $newDatabaseCount)"
}
