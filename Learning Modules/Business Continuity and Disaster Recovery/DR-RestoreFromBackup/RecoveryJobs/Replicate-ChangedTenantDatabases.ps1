<#
.SYNOPSIS
  Replicates tenant databases that have been updated in the recovery region into the original region.

.DESCRIPTION
  This script is intended to be run as a background job in the 'Repatriate-IntoOriginalRegion' script that repatriates the Wingtip SaaS app environment (apps, databases, servers e.t.c) into the origin.
  The script geo-replicates tenant databases tha have been changed in the recovery region into the original Wingtip region

.PARAMETER WingtipRecoveryResourceGroup
  Resource group in the recovery region that contains recovered resources

.PARAMETER MaxConcurrentReplicationOperations
  Maximum number of replication operations that can be run concurrently

.EXAMPLE
  [PS] C:\>.\Replicate-ChangedTenantDatabases.ps1 -WingtipRecoveryResourceGroup "sampleRecoveryResourceGroup"
#>
[cmdletbinding()]
param (
  [parameter(Mandatory=$true)]
  [String] $WingtipRecoveryResourceGroup,

  [parameter(Mandatory=$false)]
  [int] $MaxConcurrentReplicationOperations=200 
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
  Remove-AzureRmSqlDatabase -ResourceGroupName $wtpUser.ResourceGroupName -ServerName $originServerName -DatabaseName $TenantDatabase.DatabaseName -ErrorAction SilentlyContinue

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

# Get list of tenants that have updated databases in the recovery region
$tenantList = Get-ExtendedTenant -Catalog $tenantCatalog
foreach ($tenant in $tenantList)
{
  $tenantDataChanged = Test-IfTenantDataChanged -Catalog $tenantCatalog -TenantName $tenant.TenantName
  if ($tenantDataChanged)
  {
    $replicationQueue += $tenant
  }
}
$changedDatabaseCount = $replicationQueue.length 


# Remove databases that have already been replicated from queue
foreach ($tenant in $replicationQueue)
{
  $tenantServerName = $tenant.ServerName.split('.')[0]
  $tenantDatabaseProperties = Get-ExtendedDatabase -Catalog $tenantCatalog -ServerName $tenantServerName -DatabaseName $tenant.DatabaseName

  if ($tenantDatabaseProperties.RecoveryState -eq 'replicated')
  {
    # Remove databases that have already been replicated from queue
    $replicationQueue = $replicationQueue -ne $tenant
    $replicatedDatabaseCount+=1
  }
  else if ($tenantDatabaseProperties.RecoveryState -eq 'replicating')
  {
    # Get replication status of tenant database
    $replicationLink = Get-AzureRmSqlDatabaseReplicationLink `
                          -ResourceGroupName $WingtipRecoveryResourceGroup `
                          -ServerName $tenantServerName `
                          -DatabaseName $tenant.DatabaseName `
                          -PartnerResourceGroupName $wtpUser.ResourceGroupName `
                          -ErrorAction SilentlyContinue
    if ($replicationLink)
    {
      # Update database recovery state if it has completed replication
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "endReplication" -ServerName $tenantServerName -DatabaseName $tenant.DatabaseName
      $replicationQueue = $replicationQueue -ne $tenant
      $replicatedDatabaseCount+=1
    }
  }
}

# Output recovery progress 
$DatabaseRecoveryPercentage = [math]::Round($replicatedDatabaseCount/$changedDatabaseCount,2)
$DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
Write-Output "$DatabaseRecoveryPercentage% ($($replicatedDatabaseCount) of $changedDatabaseCount)"

# Issue a request to replicate changed tenant databases asynchronously till concurrent operation limit is reached
$azureContext = Get-RestAPIContext
while($operationQueue.Count -le $MaxConcurrentReplicationOperations)
{
  $currentTenant = $replicationQueue[0]

  if ($currentTenant)
  {
    $replicationQueue = $replicationQueue -ne $currentTenant
    $tenantServerName = $currentTenant.ServerName.split('.')[0]
    $tenantDatabaseProperties = Get-ExtendedDatabase -Catalog $tenantCatalog -ServerName $tenantServerName -DatabaseName $currentTenant.DatabaseName

    # Update tenant database recovery state
    $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startReplication" -ServerName $tenantServerName -DatabaseName $currentTenant.DatabaseName
    
    $operationObject = Start-AsynchronousDatabaseReplication -AzureContext $azureContext -TenantDatabase $tenantDatabaseProperties
    $databaseDetails = @{
      "ServerName" = $tenantDatabaseProperties.ServerName
      "DatabaseName" = $tenantDatabaseProperties.DatabaseName
      "ServiceObjective" = $tenantDatabaseProperties.ServiceObjective
      "ElasticPoolName" = $tenantDatabaseProperties.ElasticPoolName
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

# Check on status of database recovery operations 
while ($operationQueue.Count -gt 0)
{
  foreach($replicationJob in $operationQueue)
  {
    if (($replicationJob.IsCompleted) -and ($replicationJob.Status -eq 'RanToCompletion'))
    {
      # Start new replication operation if there are any databases left to replicate
      $currentTenant = $replicationQueue[0]
      if ($currentTenant)
      {
        $replicationQueue = $replicationQueue -ne $currentTenant
        $tenantServerName = $currentTenant.ServerName.split('.')[0]
        $tenantDatabaseProperties = Get-ExtendedDatabase -Catalog $tenantCatalog -ServerName $tenantServerName -DatabaseName $currentTenant.DatabaseName

        # Update tenant database recovery state
        $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "startReplication" -ServerName $tenantServerName -DatabaseName $currentTenant.DatabaseName
    
        $operationObject = Start-AsynchronousDatabaseReplication -AzureContext $azureContext -TenantDatabase $tenantDatabaseProperties
        $databaseDetails = @{
          "ServerName" = $tenantDatabaseProperties.ServerName
          "DatabaseName" = $tenantDatabaseProperties.DatabaseName
          "ServiceObjective" = $tenantDatabaseProperties.ServiceObjective
          "ElasticPoolName" = $tenantDatabaseProperties.ElasticPoolName
        }

        # Add operation to queue for tracking
        $operationId = $operationObject.Id
        if (!$operationQueueMap.ContainsKey("$operationId"))
        {
          $operationQueue += $operationObject
          $operationQueueMap.Add("$operationId", $databaseDetails)
        }     
      }

      # Update tenant database recovery state
      Complete-AsynchronousDatabaseReplication -replicationJobId $replicationJob.Id 

      # Remove completed job from queue for polling
      $operationQueue = $operationQueue -ne $replicationJob      

      # Output recovery progress 
      $replicatedDatabaseCount+= 1
      $DatabaseRecoveryPercentage = [math]::Round($replicatedDatabaseCount/$changedDatabaseCount,2)
      $DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
      Write-Output "$DatabaseRecoveryPercentage% ($($replicatedDatabaseCount) of $changedDatabaseCount)"               
    }
    elseif (($replicationJob.IsCompleted) -and ($replicationJob.Status -eq "Faulted"))
    {
      # Mark errorState for databases that have not been replicated 
      $databaseDetails = $operationQueueMap[$replicationJob.Id]
      $dbState = Update-TenantResourceRecoveryState -Catalog $tenantCatalog -UpdateAction "markError" -ServerName $databaseDetails.ServerName -DatabaseName $databaseDetails.DatabaseName
      
      # Remove completed job from queue for polling
      $operationQueue = $operationQueue -ne $replicationJob
    }
  }
}

# Output recovery progress 
$DatabaseRecoveryPercentage = [math]::Round($replicatedDatabaseCount/$changedDatabaseCount,2)
$DatabaseRecoveryPercentage = $DatabaseRecoveryPercentage * 100
Write-Output "$DatabaseRecoveryPercentage% ($($replicatedDatabaseCount) of $changedDatabaseCount)"

