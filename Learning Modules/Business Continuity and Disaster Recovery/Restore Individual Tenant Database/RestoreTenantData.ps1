<#
.SYNOPSIS
  Learn how to recover tenant data that has been corrupted. This script is used for a database per tenant model.  

.DESCRIPTION
  This script showcases how to recover a database that has been corrupted by a tenant.
  Corruption could happen in any number of ways from accidental table or row deletion, to an accidental addition or update of data.

.PARAMETER ResourceGroupName
  Specifies the name of the Azure resource group that contains the ShardMap manager and tenant databases

.PARAMETER User
  Specifies the 'User' value that was provided during the deployment of the Wingtip Platform sample app

.PARAMETER TenantName
  Specifies the name of the tenant that owns the database that will be recovered

.PARAMETER RestorePoint
  Specifies the point in time, as a DateTime object, that the tenant database will be restored to

.PARAMETER InPlace
  Indicates that the restored database will be created with the original database name. The original database will be renamed with a timestamp

.PARAMETER InParallel
  Indicates that the restored database will be created with the original database name. The original database will still be accessible under the key "<databasename>_old"

.NOTES
  Name: RestoreTenantData
  Author: Ayo Olubeko
  Requires: Wingtip SaaS App from Saas-in-a-box Module 1, ShardManagement.psm1 elastic database tools library
  Version History: 1.0
 
.EXAMPLE
  [PS] C:\>.\RestoreTenantdata.ps1 -ResourceGroupName "Wingtip-user1" -User "user1" -TenantName <TenantName> -RestorePoint <UTCDate> -InParallel
#>
[cmdletbinding()]
param (
    [parameter(Mandatory=$true)][string]$User,
    [parameter(Mandatory=$true)][string]$TenantName,
    [parameter(Mandatory=$true)][DateTime]$RestorePoint,
    [parameter(Mandatory=$false)][string]$ResourceGroupName="Wingtip-user1",
    [parameter(Mandatory=$true, ParameterSetName="InPlace")][switch]$InPlace,
    [parameter(Mandatory=$true, ParameterSetName="InParallel")][switch]$InParallel
)

#---------------------------------------------------------[User variables]--------------------------------------------------------
$catalogServerName = "catalog-" + $User
$catalogDatabaseName = "customercatalog"
$catalogServerAdminLogin = "developer"
$catalogServerAdminPassword = "P@ssword1"

$customerServerAdminLogin = "developer"
$customerServerAdminPassword = "P@ssword1"

$shardMapManagerName = "customercatalog"
$shardMapName = "customercatalog"
$VerbosePreference = "Continue"

#----------------------------------------------------------[Functions]----------------------------------------------------------
<#
.SYNOPSIS
    Returns the knuth multiplicate hash of a tenant name. This value is used as the key for the ShardMap
#>
function Get-TenantKey
{
    param
    (
        # Tenant name 
        [parameter(Mandatory=$true)][String]$TenantBusinessName
    )

    # Return Knuth multiplicative hash of tenant name 
    [Type]$TenantInitialization = [WingtipApp_TenantRegistration.TenantRegistration]
    $tenantKey = $TenantInitialization::GetTenantId($TenantBusinessName)
    return $tenantKey
    
    # Return utf8 encoding of tenant name 
    # $utf8 = New-Object -TypeName System.Text.UTF8Encoding
    # $tenantKey = $utf8.GetBytes($TenantBusinessName)
    # $tenantKey = [bitconverter]::ToInt32($tenantKey,0)
    # return $tenantKey
}
<#
.SYNOPSIS
    Facilitate login to Azure and select subscription that will be used
#>
function InitSubscription
{
    # Get current Azure context 
    try 
    {
        # Use previous login credentials if already logged in 
        $Azurecontext = Get-AzureRmContext
        Write-Output "You are signed-in as: $($Azurecontext.Account)"
        Write-Output $Azurecontext
    }
    catch
    {
        #Login to Azure 
        Login-AzureRmAccount
        $Azurecontext = Get-AzureRmContext
        Write-Output "You are signed-in as: $($Azurecontext.Account)"

        # Get subscription list 
        $subscriptionList = Get-AzureRmSubscription
        if($subscriptionList.Length -lt 1)
        {
            Write-Error "Your Azure account does not have any active subscriptions. Exiting..."
            exit 
        }
        elseif($subscriptionList.Length -eq 1)
        {
            Select-AzureRmSubscription -SubscriptionId $subscriptionList[0].SubscriptionId > $null
        }
        elseif($subscriptionList.Length -gt 1)
        {
            # Display available subscriptions 
            $index = -1
            foreach($subscription in $subscriptionList)
            {
                $index++
                $subscription | Add-Member -type NoteProperty -name "RowNumber" -value $index
            }

            # Prompt for selection 
            Write-Output "Your Azure subcriptions: "
            $subscriptionList | Format-Table RowNumber,SubscriptionId,SubscriptionName -AutoSize
            $rowSelection = Read-Host "Enter the row number (0 - $index) of a subscription"
            
            # Select single Azure subscription for session 
            try
            {
                Select-AzureRmSubscription -SubscriptionId $subscriptionList[$index] > $null
            }
            catch
            {
                Write-Error 'Invalid subscription ID provided. Exiting...'
                exit 
            }
        }
    }
}
<#
.SYNOPSIS
    Retry input command in case of intermittent network failure. Adapted from 'Retry-command' function created by Richard Kerslake @Endjin.
#>
function RetryCommandIfError
{
    param (
    [Parameter(Mandatory=$true,ParameterSetName="command")][string]$command, 
    [Parameter(Mandatory=$true,ParameterSetName="command")][hashtable]$args, 
    [Parameter(Mandatory=$true,ParameterSetName="object")][Object[]]$inputObject,
    [Parameter(Mandatory=$true,ParameterSetName="object")][String]$methodName,
    [Parameter(Mandatory=$false,ParameterSetName="object")][Object[]]$methodParameters,
    [Parameter(Mandatory=$false)][int]$retries = 5, 
    [Parameter(Mandatory=$false)][int]$secondsDelay = 2
    )
    
    if ($command)
    {
        $args.ErrorAction = "Stop"
    }
    
    $retrycount = 0
    $returnValue = $null
    $completed = $false

    while (-not $completed)
    {
        try
        {
            if ($command)
            {
                $returnValue = & $command @args
                Write-Verbose ("Command [{0}] succeeded." -f $command)
                $completed = $true
            }
            elseif ($inputObject -and $methodParameters)
            {
                $returnValue = $inputObject | % { $_.$methodName.Invoke($methodParameters) }
                Write-Verbose ("$inputObject.$methodName succeeded.")
                $completed = $true
            }
            elseif ($inputObject)
            {
                $returnValue = $inputObject | % { $_.$methodName.Invoke() }
                Write-Verbose ("$inputObject.$methodName succeeded.")
                $completed = $true
            }
        }
        catch
        {
            if (($retrycount -ge $retries) -and ($command))
            {
                Write-Verbose ("Command '$command' failed the maximum number of $retrycount times.")
                throw
            }
            elseif (($retrycount -ge $retries) -and ($inputObject))
            {
                Write-Verbose ("$inputObject.$methodName failed the maximum number of $retrycount times.")
                throw
            }
            elseif ($command) 
            {
                Write-Verbose ("Command '$command' failed. Retrying in $retrycount seconds.")
                Start-Sleep $secondsDelay
                $secondsDelay = $secondsDelay * 2
                $retrycount++
            }
            elseif ($inputObject)
            {
                Write-Verbose ("$inputObject.$methodName failed. Retrying in $retrycount seconds.")
                Start-Sleep $secondsDelay
                $secondsDelay = $secondsDelay * 2
                $retrycount++
            }
        }
    }
    return $returnValue
}
<#
.SYNOPSIS
    Check if the input restore point is valid for the current tenant database in the catalog. 
    If valid, return the current tenant database.
    Otherwise search for any available databases from the same tenant and return that.
#>
function Get-DatabaseForRestorePoint
{
    param (
     [Parameter(Mandatory=$true)][Microsoft.Azure.Commands.Sql.Database.Model.AzureSqlDatabaseModel]$InputTenantDatabase,
     [Parameter(Mandatory=$true)][DateTime]$InputRestorePoint
    )

    # Strip snapshot time from name of the database if it has been previously restored
    $tenantDatabaseStem = ($InputTenantDatabase.DatabaseName).Split('_')[0]
    $restoreDatabase = $null

    # Validate restore point 
    $oldestRestorePoint = $InputTenantDatabase.EarliestRestoreDate
    $latestRestorePoint = $InputTenantDatabase.tags["SnapshotTime"]
    $restoredInstanceCheck = $InputTenantDatabase.tags["RestoreTime"]
    
    if (($oldestRestorePoint -gt $InputRestorePoint) -or ($latestRestorePoint -lt $InputRestorePoint))
    {
        if (!$latestRestorePoint -and !$restoredInstanceCheck)
        {
            $restoreDatabase = $InputTenantDatabase
        }
        else
        {
            $statusMessage = "The input restore point is not within the backup range of the current tenant database. Searching for earlier databases from the same tenant..."
            Write-Verbose $statusMessage
            
            # Get list of all databases in customers server 
            $databaseParameters = @{
                ResourceGroupName = $InputTenantDatabase.ResourceGroupName
                ServerName = $InputTenantDatabase.ServerName
            }
            $databaseList = Get-AzureRmSqlDatabase @databaseParameters
            
            # Find the first available tenant database that contain the restore point
            $tenantBackupFound = $false 
            foreach ($database in $databaseList)
            {
                $databaseStem = ($database.DatabaseName).Split('_')[0]
                if ($databaseStem -eq $tenantDatabaseStem)
                {
                    $oldestRestorePoint = $database.EarliestRestoreDate
                    $latestRestorePoint = $database.tags["SnapshotTime"]

                    if (($oldestRestorePoint -lt $InputRestorePoint) -and ($latestRestorePoint -gt $InputRestorePoint))
                    {
                        $statusMessage = "Using '$($database.DatabaseName)' backup database for tenant restore..."
                        Write-Verbose $statusMessage
                        $restoreDatabase = $database
                        $tenantBackupFound = $true 
                        break
                    }
                    elseif(($oldestRestorePoint -lt $InputRestorePoint) -and (!$latestRestorePoint))
                    {
                        $statusMessage = "Using '$($database.DatabaseName)' backup database for tenant restore..."
                        Write-Verbose $statusMessage
                        $restoreDatabase = $database
                        $tenantBackupFound = $true 
                        break
                    }
                }
            }

            if (!$tenantBackupFound)
            {
                Write-Error "No earlier tenant backups with backup range including $InputRestorePoint. Earliest restore point for tenant: $oldestRestorePoint"
            }
        }
    }
    elseif (($oldestRestorePoint -lt $InputRestorePoint) -and ($latestRestorePoint -gt $InputRestorePoint))
    {
        $restoreDatabase = $InputTenantDatabase
    }

    return $restoreDatabase
}

#----------------------------------------------------------[Initializations]----------------------------------------------------------

# Stop execution on error 
$ErrorActionPreference = "Stop"

# Login to Azure and select subscription 
InitSubscription

# Import elastic database tools powershell module
Import-Module $PSScriptRoot\ShardManagement -Force

#Import Wingtip App Tenant Registration module 
Add-Type -Path "$PSScriptRoot\WingtipApp_TenantRegistration.dll"

# Get Shardmap Manager database 
Write-Output "Acquiring catalog database '$catalogDatabaseName'..."
$shardMapParameters = @{
    ResourceGroupName = $ResourceGroupName
    ServerName = $catalogServerName 
    DatabaseName = $catalogDatabaseName
    ErrorAction = "SilentlyContinue"
}
$shardMapManagerDatabase = Get-AzureRmSqlDatabase @shardMapParameters

# Exit script if the ShardMap manager database does not exist 
if (!$shardMapManagerDatabase)
{
    Write-Output "Could not find '$catalogDatabaseName' database in '$catalogServerName' server, '$ResourceGroupName' resource group. Exiting..."
    exit
}

# Get shardmap Manager instance 
Write-Output "Acquiring '$shardMapManagerName' shardmap manager from the catalog database..."
$shardMapManagerParameters = @{
    UserName = $catalogServerAdminLogin
    Password = $catalogServerAdminPassword 
    SqlServerName = "$catalogServerName.database.windows.net"
    SqlDatabaseName = $catalogDatabaseName
}
$shardMapManagerInstance = RetryCommandIfError -command Get-ShardMapManager -args $shardMapManagerParameters

# Exit script if ShardMap manager database does not have a ShardMap manager 
if (!($shardMapManagerInstance))
{
    Write-Output "Could not find '$shardMapManagerName' shard map manager in the database. Exiting..."
    exit
}

# Get ShardMap Instance 
Write-Output "Acquiring '$shardMapName' shardmap instance from shardmap..."
$shardMapParameters = @{
    KeyType = $([int])
    ShardMapManager = $shardMapManagerInstance
    ListShardMapName = $shardMapName
}
$shardMapInstance = RetryCommandIfError -command Get-ListShardMap -args $shardMapParameters

# Exit script if ShardMap not found
if (!($shardMapInstance))
{
    Write-Output "Could not find '$shardMapName' ListShardMap in '$shardMapManagerName' shardmap Manager. Exiting..."
    exit
}

# Get tenant Shards 
Write-Output "Acquiring tenant shards from '$shardMapName' shardmap instance..."
$shardList = Get-Shards -ShardMap $shardMapInstance

# Exit script if no shards found in the shardmap 
if (!$shardList)
{
    Write-Output "No tenant shards were found in the ShardMap. Exiting..."
    exit 
}

#-----------------------------------------------------------[Main Script]------------------------------------------------------------

# Sanitize input tenant name 
$TenantName = ($TenantName -replace '\s', '').ToLower()
# Get tenant hash key 
$tenantHashKey = Get-TenantKey $TenantName

# Check if tenant in shardmap 
try
{
    $shardMapInstance.GetMappingForKey($tenantHashKey) > $null
}
catch
{
    $shardList | Format-Table -AutoSize
    Write-Output "Tenant '$TenantName' does not exist in shardmap '$shardMapName'. Exiting..."
    exit 
}

# Mark tenant as offline to prevent further access
Write-Output "Marking tenant offline..."
$tenantMapping = $shardMapInstance.GetMappingForKey($tenantHashKey)
if ($tenantMapping.Status)
{
    RetryCommandIfError -inputObject $shardMapInstance -methodName "MarkMappingOffline" -methodParameters @($tenantMapping) | Format-List
}

# Get tenant server-name and database-name 
$tenantShard = $tenantMapping.Shard
$tenantDatabaseName = $tenantShard.Location.Database  
$fullyQualifiedTenantServer = $tenantShard.Location.Server
# Get hostname from fully-qualified server domain name 
$tenantServerName = $fullyQualifiedTenantServer.Split('.')[0]

# Get Azure SQL database from tenant server-name and database-name
$tenantDatabaseParameters = @{
    ResourceGroupName = $ResourceGroupName
    ServerName = $tenantServerName
    DatabaseName = $tenantDatabaseName
}
$tenantAzureDatabase = Get-AzureRmSqlDatabase @tenantDatabaseParameters

# Strip snapshot time from name of the database if it has been previously restored
$parsedDatabaseName = ($tenantAzureDatabase.DatabaseName).Split('_')[0]

# Append timestamp to original database name to construct temporary name of restored database instance
$currentTime = [DateTime]::UtcNow
$restoreDatabaseName = $parsedDatabaseName + "_" + $currentTime.ToString('yyyy-MM-ddTHH-mm-ssZ')

# Validate restore point and get restore source database
$restoreSource = Get-DatabaseForRestorePoint -InputTenantDatabase $tenantAzureDatabase -InputRestorePoint $RestorePoint

# Construct restored database parameters to match original database parameters 
$restoreDbParameters = @{
    PointInTime = $RestorePoint
    ResourceGroupName = $ResourceGroupName
    ServerName = $restoreSource.ServerName
    TargetDatabaseName = $restoreDatabaseName
    ResourceId = $restoreSource.ResourceID
    Edition = $restoreSource.Edition
    ServiceObjectiveName = $restoreSource.CurrentServiceObjectiveName
}

# If original database is inside an elastic pool, restore to the same elastic pool
if ($restoreSource.ElasticPoolName -ne $null)
{
    # Remove individual service objective parameters, and add elastic pool parameters 
    $restoreDbParameters.remove("Edition")
    $restoreDbParameters.remove("ServiceObjectiveName")
    $restoreDbParameters["ElasticPoolName"] = $restoreSource.ElasticPoolName
} 

# Restore database to input point-in-time
Write-Output "Restoring '$TenantName' database to '$restoreDatabaseName' ..."
$restoredTenantInstance = Restore-AzureRmSqlDatabase -FromPointInTimeBackup @restoreDbParameters

# Tag restored database instance with restore time 
$tags = $restoredTenantInstance.Tags
if ($tags["RestoreTime"])
{
    $tags["RestoreTime"] = $currentTime.ToString('u')
}
else
{
    $tags += @{"RestoreTime"=$currentTime.ToString('u')}
}

$updateTagParameters = @{
    ResourceGroupName = $restoredTenantInstance.ResourceGroupName
    ServerName = $restoredTenantInstance.ServerName
    DatabaseName = $restoredTenantInstance.DatabaseName
    Tags = $tags
}
$restoredTenantInstance = Set-AzureRmSqlDatabase @updateTagParameters

# Construct new name of original database instance based on input parameters 
if ($InPlace)
{
    # Get current time 
    $currentTime = [DateTime]::UtcNow
    $targetDatabaseName = $parsedDatabaseName + "_at_" + $currentTime.ToString('yyyy-MM-ddTHH-mm-ssZ')
}
elseif ($InParallel)
{ 
    $targetDatabaseName = $parsedDatabaseName + "_old"
}

# Tag original database instance with snapshot time
Write-Output "Tagging original SQL database instance with current snapshot time ..."
$tags = $tenantAzureDatabase.Tags
if (!$tags["SnapshotTime"])
{
    $tags += @{"SnapshotTime"=$currentTime.ToString('u')}
}

$updateTagParameters = @{
    ResourceGroupName = $tenantAzureDatabase.ResourceGroupName
    ServerName = $tenantAzureDatabase.ServerName
    DatabaseName = $tenantAzureDatabase.DatabaseName
    Tags = $tags
}
$tenantAzureDatabase = Set-AzureRmSqlDatabase @updateTagParameters

# Rename original tenant database 
Write-Output "Original SQL database instance: [$($tenantAzureDatabase.DatabaseName)] -> [$targetDatabaseName]"
Write-Output "Restored SQL database instance: [$($restoredTenantInstance.DatabaseName)] -> [$parsedDatabaseName]"

Write-Output "Renaming SQL database instances ..."
$commandText = "ALTER DATABASE [$($tenantAzureDatabase.DatabaseName)] MODIFY NAME = [$targetDatabaseName];
                ALTER DATABASE [$($restoredTenantInstance.DatabaseName)] MODIFY NAME = [$parsedDatabaseName];
               "
$SqlCmdParameters = @{
    Username = $customerServerAdminLogin
    Password = $customerserverAdminPassword
    ServerInstance = $tenantAzureDatabase.ServerName + ".database.secure.windows.net"
    Database = "master"
    ConnectionTimeout = 30
    QueryTimeout = 30
    EncryptConnection = $True
    Query = $commandText
}
Invoke-Sqlcmd @SqlCmdParameters

$originalDatabaseProperties = @{
    DatabaseName = $targetDatabaseName
    FullyQualifiedServerName = $tenantAzureDatabase.ServerName + ".database.windows.net"
    ResourceGroup = $tenantAzureDatabase.ResourceGroupName
    TenantHashKey = Get-TenantKey -TenantBusinessName $targetDatabaseName
}

$restoredDatabaseProperties = @{
    DatabaseName = $parsedDatabaseName
    FullyQualifiedServerName = $tenantAzureDatabase.ServerName + ".database.windows.net"
    ResourceGroup = $tenantAzureDatabase.ResourceGroupName
    TenantHashKey = Get-TenantKey -TenantBusinessName $parsedDatabaseName
}

# Get recovery manager that will be used to rebuild tenant mappings 
$tenantRecoveryManager = $shardMapManagerInstance.getRecoveryManager()

# Rebuild shardmap tenant mappings
if ($InParallel)       
{
    # Detach original database shard from shard map. This allows the restored instance to be added to the shard map
    Write-Output "Detaching restored database instance from shard map ..."
    $tenantRecoveryManager.DetachShard($tenantShard.Location, $shardMapName)

    # Add original renamed database instance shard to shard map 
    Write-Output "Attaching original renamed database instance '$($originalDatabaseProperties.DatabaseName)' to shardmap ..."
    $renamedOriginalShardLocation = New-Object Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardLocation($originalDatabaseProperties.FullyQualifiedServerName, $originalDatabaseProperties.DatabaseName)
    $tenantRecoveryManager.AttachShard($renamedOriginalShardLocation, $shardMapName)

    # Delete all mappings from original renamed database instance and existing shard
    Write-Output "Deleting shard mappings from original renamed database instance ..."
    $shardMapMismatches = $tenantRecoveryManager.DetectMappingDifferences($renamedOriginalShardLocation, $shardMapName)
    $resolutionStrategy = [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.Recovery.MappingDifferenceResolution]::KeepShardMapMapping
    foreach ($mismatch in $shardMapMismatches)
    {
        $tenantRecoveryManager.ResolveMappingDifferences($mismatch, $resolutionStrategy); 
    }
    if ($shardMapInstance.TryGetShard($renamedOriginalShardLocation, [ref]$tenantShard))
    {
        $shardMapInstance.DeleteShard($tenantShard)
    }

    # Add new shard for original renamed database instance
    Write-Output "Adding new shard mappings for original database instance '$($originalDatabaseProperties.DatabaseName)' ..."
    Add-Shard -ShardMap $shardMapInstance -SqlServerName $originalDatabaseProperties.FullyQualifiedServerName -SqlDatabaseName $originalDatabaseProperties.DatabaseName

    # Add new key mapping for original renamed database instance
    $listMappingParameters = @{
        KeyType = $([int])
        ListShardMap = $shardMapInstance
        SqlServerName = $originalDatabaseProperties.FullyQualifiedServerName
        SqlDatabaseName = $originalDatabaseProperties.DatabaseName
        ListPoint = $originalDatabaseProperties.TenantHashKey
    }
    Add-ListMapping @listMappingParameters

    # Add restored database instance to shard map
    Write-Output "Attaching restored database instance '$($restoredDatabaseProperties.DatabaseName)' to shardmap ..."
    $restoredDatabaseShardLocation = New-Object Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardLocation($restoredDatabaseProperties.FullyQualifiedServerName, $restoredDatabaseProperties.DatabaseName)
    $tenantRecoveryManager.AttachShard($restoredDatabaseShardLocation, $shardMapName)

    # Sync changes to global shard map 
    Write-Output "Syncing changes with global shard map ..."
    $shardMapMismatches = $tenantRecoveryManager.DetectMappingDifferences($restoredDatabaseShardLocation, $shardMapName)
    $resolutionStrategy = [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.Recovery.MappingDifferenceResolution]::KeepShardMapping
    foreach ($mismatch in $shardMapMismatches)
    {
        $tenantRecoveryManager.ResolveMappingDifferences($mismatch, $resolutionStrategy); 
    }
} 
elseif ($InPlace)                      
{
    Write-Output "Syncing changes with global shard map ..."
    $shardMapMismatches = $tenantRecoveryManager.DetectMappingDifferences($tenantShard.Location, $shardMapName)
    
    # Use local shard map as source of truth if there's a conflict 
    $resolutionStrategy = [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.Recovery.MappingDifferenceResolution]::KeepShardMapping
    foreach ($mismatch in $shardMapMismatches)
    {
        $tenantRecoveryManager.ResolveMappingDifferences($mismatch, $resolutionStrategy); 
    }
}

#Enable tenant access to the database(s)
if ($InParallel)
{
    Write-Output "Marking tenants '$($restoredDatabaseProperties.DatabaseName)',and '$($originalDatabaseProperties.DatabaseName)' online ..."
    $originalTenantMapping = $shardMapInstance.GetMappingForKey($originalDatabaseProperties.TenantHashKey)
    $restoredTenantMapping = $shardMapInstance.GetMappingForKey($restoredDatabaseProperties.TenantHashKey)
    
    # Mark restored and original database tenants online 
    RetryCommandIfError -inputObject $shardMapInstance -methodName "MarkMappingOnline" -methodParameters @($originalTenantMapping) | Format-List
    RetryCommandIfError -inputObject $shardMapInstance -methodName "MarkMappingOnline" -methodParameters @($restoredTenantMapping) | Format-List
}
elseif($InPlace)
{
    Write-Output "Marking tenant '$($restoredDatabaseProperties.DatabaseName)'' online..."
    $tenantMapping = $shardMapInstance.GetMappingForKey($restoredDatabaseProperties.TenantHashKey)

    # Mark restored tenant online 
    RetryCommandIfError -inputObject $shardMapInstance -methodName "MarkMappingOnline" -methodParameters @($tenantMapping) | Format-List
}



