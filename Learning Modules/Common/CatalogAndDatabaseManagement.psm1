<#
.Synopsis
  This module implements a tenant-focused catalog and database API over the Shard Management APIs. 
  It simplifies catalog management by focusing on operations done to a tenant and tenant databases.
#>

Import-Module $PSScriptRoot\..\WtpConfig -Force
Import-Module $PSScriptRoot\..\ProvisionConfig -Force
Import-Module $PSScriptRoot\AzureShardManagement -Force
Import-Module $PSScriptRoot\SubscriptionManagement -Force
Import-Module sqlserver -ErrorAction SilentlyContinue

# Stop execution on error
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Adds extended tenant meta data associated with a mapping using the raw value of the tenant key
#>
function Add-ExtendedTenantMetaDataToCatalog
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [int32]$TenantKey,

        [parameter(Mandatory=$true)]
        [string]$TenantName,

        [parameter(Mandatory=$false)]
        [string]$TenantServicePlan = 'standard'
    )

    $config = Get-Configuration

    # Get the raw tenant key value used within the shard map
    $tenantRawKey = Get-TenantRawKey ($TenantKey)
    $rawkeyHexString = $tenantRawKey.RawKeyHexString


    # Add the tenant name into the Tenants table
    $commandText = "
        MERGE INTO Tenants as [target]
        USING (VALUES ($rawkeyHexString, '$TenantName', '$TenantServicePlan', CURRENT_TIMESTAMP)) AS source
            (TenantId, TenantName, ServicePlan, LastUpdated)
        ON target.TenantId = source.TenantId
        WHEN MATCHED THEN
            UPDATE SET 
                TenantName = source.TenantName, 
                ServicePlan = source.ServicePlan,
                LastUpdated = source.LastUpdated
        WHEN NOT MATCHED THEN
            INSERT (TenantId, TenantName, ServicePlan, RecoveryState, LastUpdated)
            VALUES (source.TenantId, source.TenantName, source.ServicePlan, 'n/a', CURRENT_TIMESTAMP);"

    Invoke-SqlAzureWithRetry `
        -ServerInstance $Catalog.FullyQualifiedServerName `
        -Username $config.TenantAdminuserName `
        -Password $config.TenantAdminPassword `
        -Database $Catalog.Database.DatabaseName `
        -Query $commandText `
        -ConnectionTimeout 30 `
        -QueryTimeout 30 `
}


<#
.SYNOPSIS
    Registers the tenant database in the catalog. Additionally, the tenant name is stored as extended tenant meta data.
#>
function Add-TenantDatabaseToCatalog
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [string]$TenantName,

        [parameter(Mandatory=$true)]
        [int32]$TenantKey,

        [parameter(Mandatory=$true)]
        [object]$TenantDatabase,

        [parameter(Mandatory=$true)]
        [string]$TenantServerName,

        [parameter(Mandatory=$false)]
        [string]$TenantServicePlan = 'standard'
    )

    $fullyQualifiedTenantServerName = $TenantServerName + ".database.windows.net"
    
    # Add the database to the catalog shard map (idempotent)
    Add-Shard -ShardMap $Catalog.ShardMap `
        -SqlServerName $fullyQualifiedTenantServerName `
        -SqlDatabaseName $TenantDatabase.DatabaseName

    # Add the tenant-to-database mapping to the catalog (idempotent)
    Add-ListMapping `
        -KeyType $([int]) `
        -ListShardMap $Catalog.ShardMap `
        -SqlServerName $fullyQualifiedTenantServerName `
        -SqlDatabaseName $TenantDatabase.DatabaseName `
        -ListPoint $TenantKey

    # Add the tenant name to the catalog as extended meta data (idempotent)
    Add-ExtendedTenantMetaDataToCatalog `
        -Catalog $Catalog `
        -TenantKey $TenantKey `
        -TenantName $TenantName `
        -TenantServicePlan $TenantServicePlan

    # Add server details to catalog as extended meta data (idempotent)
    Set-ExtendedServer -Catalog $Catalog -Server $TenantDatabase

    # Add database details to catalog as extended meta data (idempotent)
    Set-ExtendedDatabase -Catalog $Catalog -Database $TenantDatabase

    # Add elastic pool details to catalog as extended meta data (idempotent)
    if ($TenantDatabase.ElasticPoolName)
    {
        $tenantElasticPool = Get-AzureRmSqlElasticPool `
                                -ResourceGroupName $TenantDatabase.ResourceGroupName `
                                -ServerName $TenantDatabase.ServerName `
                                -ElasticPoolName $TenantDatabase.ElasticPoolName

        Set-ExtendedElasticPool -Catalog $Catalog -ElasticPool $tenantElasticPool    
    }
    
}

<#
.SYNOPSIS
    Disable change tracking on a tenant database. 
#>
function Disable-ChangeTrackingForTenant
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [string] $TenantName
    )

    $config = Get-Configuration
    $adminUserName = $config.TenantAdminUserName
    $adminPassword = $config.TenantAdminPassword
   
    $tenantObject = Get-Tenant -Catalog $Catalog -TenantName $TenantName
    $fullyQualifiedServerName = $tenantObject.Database.ServerName + ".database.windows.net"

    $queryText = "
            SELECT      schm.name AS schemaName, 
                        tbl.name AS tableName
            FROM        sys.tables tbl
            JOIN        sys.schemas schm ON (schm.schema_id = tbl.schema_id)
            JOIN        sys.change_tracking_tables ctt ON (tbl.object_id = ctt.object_id)
            "

    # Get database tables that do have change tracking enabled 
    $trackedTables = Invoke-SqlAzureWithRetry `
        -Username $adminUserName `
        -Password $adminPassword `
        -ServerInstance $fullyQualifiedServerName `
        -Database $tenantObject.Database.DatabaseName `
        -ConnectionTimeout 45 `
        -Query $queryText `

    $queryText = ""
    foreach ($table in $trackedTables)
    {
        queryText += "ALTER TABLE [$($table.schemaName)].[$($table.tableName)] DISABLE CHANGE_TRACKING `n"
    }
    queryText += "ALTER DATABASE $($tenantObject.Database.DatabaseName) SET CHANGE_TRACKING = OFF"

    # Disable change tracking on tenant database
    $commandOutput = Invoke-SqlAzureWithRetry `
        -Username $adminUserName `
        -Password $adminPassword `
        -ServerInstance $fullyQualifiedServerName `
        -Database $tenantObject.Database.DatabaseName `
        -ConnectionTimeout 45 `
        -Query $queryText `
}

<#
.SYNOPSIS
    Enables change tracking on a tenant database. This is particularly useful in a recovery scenario to track tenant data that needs to be repatriated
#>
function Enable-ChangeTrackingForTenant
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [string] $TenantServerName,

        [parameter(Mandatory=$true)]
        [string] $TenantDatabaseName,       

        [parameter(Mandatory=$false)]
        [int32] $RetentionPeriod = 10
    )

    $config = Get-Configuration
    $adminUserName = $config.TenantAdminUserName
    $adminPassword = $config.TenantAdminPassword
   
    $fullyQualifiedTenantServerName = $TenantServerName + ".database.windows.net"

    # Enable change tracking if not enabled on tenant database
    $queryText = "
        IF NOT EXISTS (SELECT * FROM sys.change_tracking_databases)
        ALTER DATABASE $TenantDatabaseName SET CHANGE_TRACKING = ON (CHANGE_RETENTION = $RetentionPeriod DAYS, AUTO_CLEANUP = ON);`n           
        "
    $changeTrackingEnabled = Invoke-SqlAzureWithRetry `
                                -UserName $adminUserName `
                                -Password $adminPassword `
                                -ServerInstance $fullyQualifiedTenantServerName `
                                -Database $TenantDatabaseName `
                                -ConnectionTimeout 45 `
                                -Query $queryText

    # Get database tables that do not have change tracking enabled
    $queryText = "
            SELECT      schm.name AS schemaName, 
                        tbl.name AS tableName
            FROM        sys.tables tbl
            JOIN        sys.schemas schm ON (schm.schema_id = tbl.schema_id)
            LEFT JOIN   sys.change_tracking_tables ctt ON (tbl.object_id = ctt.object_id)
            WHERE       (schm.schema_id = 1 AND ctt.object_id IS NULL);
            "     
    $untrackedTables = Invoke-SqlAzureWithRetry `
        -Username $adminUserName `
        -Password $adminPassword `
        -ServerInstance $fullyQualifiedTenantServerName `
        -Database $TenantDatabaseName `
        -ConnectionTimeout 45 `
        -Query $queryText `

    # Enable change tracking on untracked tables 
    if ($untrackedTables)
    {
        $queryText = ""
        foreach ($table in $untrackedTables)
        {
            $queryText += "ALTER TABLE [$($table.schemaName)].[$($table.tableName)] ENABLE Change_tracking WITH (TRACK_COLUMNS_UPDATED = ON) `n"
        }
        
        # Enable change tracking on tenant database
        $commandOutput = Invoke-SqlAzureWithRetry `
            -Username $adminUserName `
            -Password $adminPassword `
            -ServerInstance $fullyQualifiedTenantServerName `
            -Database $TenantDatabaseName `
            -ConnectionTimeout 45 `
            -Query $queryText `
    }
}

<#
.SYNOPSIS
    Finds names of tenants that match an input string.
#>
function Find-TenantNames
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [string] $SearchString
    )
    Test-LegalNameFragment $SearchString

    $config = Get-Configuration

    $adminUserName = $config.CatalogAdminUserName
    $adminPassword = $config.CatalogAdminPassword
   
    $commandText = "SELECT TenantName from Tenants WHERE TenantName LIKE '%$SearchString%'";
             
    $tenantNames = Invoke-SqlAzureWithRetry `
        -Username $adminUserName `
        -Password $adminPassword `
        -ServerInstance $catalog.FullyQualifiedServerName `
        -Database $catalog.Database.DatabaseName `
        -ConnectionTimeout 45 `
        -Query $commandText `

    return $tenantNames            
}


<#
.SYNOPSIS
    Initializes and returns a catalog object based on the active catalog database. 
    The returned catalog object contains the initialized shard map manager and shard map, which can be used to access
    the associated databases (shards) and tenant key mappings.
#>
function Get-Catalog
{
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [parameter(Mandatory=$true)]
        [string]$WtpUser
    )
    $config = Get-Configuration
    $retries = 0
    $retryLimit = 2
    $sleepInterval = 5

    # Resolve DNS alias to get current catalog server
    do
    {
        try
        {
            $catalogAlias = $config.ActiveCatalogAliasStem + $WtpUser + ".database.windows.net"
            $catalogServerName = Get-ServerNameFromAlias $catalogAlias

            # Find catalog server in Azure 
            $catalogServer = Find-AzureRmResource -ResourceNameEquals $catalogServerName -ResourceType "Microsoft.Sql/servers"
            $fullyQualifiedServerName = $catalogServer.Name + ".database.windows.net"

            # Check catalog database exists
            $catalogDatabase = Get-AzureRmSqlDatabase `
                -ResourceGroupName $catalogServer.ResourceGroupName `
                -ServerName $catalogServer.Name `
                -DatabaseName $config.CatalogDatabaseName `
                -ErrorAction Stop

            # Initialize shard map manager from catalog database
            [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManager]$shardMapManager = Get-ShardMapManager `
                -SqlServerName $fullyQualifiedServerName `
                -UserName $config.CatalogAdminUserName `
                -Password $config.CatalogAdminPassword `
                -SqlDatabaseName $config.CatalogDatabaseName

            if (!$shardmapManager)
            {
                throw "Failed to initialize shard map manager from '$($config.CatalogDatabaseName)' database. Ensure catalog is initialized by opening the Events app and try again."
            }

            # Initialize shard map
            [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMap]$shardMap = Get-ListShardMap `
                -KeyType $([int]) `
                -ShardMapManager $shardMapManager `
                -ListShardMapName $config.CatalogShardMapName

            If (!$shardMap)
            {
                throw "Failed to load shard map '$($config.CatalogShardMapName)' from '$($config.CatalogDatabaseName)' database. Ensure catalog is initialized by opening the Events app and try again."
            }
            else
            {
                $catalog = New-Object PSObject -Property @{
                    ShardMapManager=$shardMapManager
                    ShardMap=$shardMap
                    CatalogAlias = $catalogAlias
                    FullyQualifiedServerName = $fullyQualifiedServerName
                    Database = $catalogDatabase
                }

                return $catalog
            }
        }
        catch
        {
            if ($retries -gt $retryLimit)
            {
                throw $_.Exception.Message
            }
            else
            {
                $retries+=1
                Start-Sleep $sleepInterval
            }
        }
    } while ($true)   
    
}


<#
.SYNOPSIS
    Returns the active and any restored tenant databases for specified tenant.
#>
function Get-DatabasesForTenant
{
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [int32]$TenantKey
    )

    $tenantDatabaseList = @()
    $tenantMapping = ($Catalog.ShardMap).GetMappingForKey($tenantKey)
    $tenantDatabaseName = $tenantMapping.Shard.Location.Database
    $fullyQualifiedTenantServerName = $tenantMapping.Shard.Location.Server
    $tenantServerName = $fullyQualifiedTenantServerName.split('.')[0]

    # Find tenant server in Azure 
    $tenantServer = Find-AzureRmResource -ResourceNameEquals $tenantServerName -ResourceType "Microsoft.Sql/servers"

    # Get active tenant database 
    $activeTenantDatabase = Get-AzureRmSqlDatabase `
                                -ResourceGroupName $tenantServer.ResourceGroupName `
                                -ServerName $tenantServerName `
                                -DatabaseName $tenantDatabaseName `
                                -ErrorAction SilentlyContinue

    # Get restored tenant database 
    $restoredTenantDatabaseName = $tenantDatabaseName + "-old"
    $restoredTenantDatabase = Get-AzureRmSqlDatabase `
                                -ResourceGroupName $tenantServer.ResourceGroupName `
                                -ServerName $tenantServerName `
                                -DatabaseName $restoredTenantDatabaseName `
                                -ErrorAction SilentlyContinue

    if ($activeTenantDatabase)
    {
        $tenantDatabaseList += $activeTenantDatabase
    }

    if ($restoredTenantDatabase)
    {
        $tenantDatabaseList += $restoredTenantDatabase
    }

    return $tenantDatabaseList
}


<#
.SYNOPSIS
    Returns extended database metadata for a specified server from the catalog.
#>
function Get-ExtendedDatabase{
    param (
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [string]$ServerName,

        [string]$DatabaseName
    )

    if ($DatabaseName -and -not $ServerName)
    {
        throw "Must specify a ServerName if specifying a DatabaseName"
    }

    $config = Get-Configuration

    $commandText = "SELECT DatabaseName, ServerName, ServiceObjective, ElasticPoolName, State, RecoveryState, RecoveryChecksum, LastUpdated FROM [dbo].[Databases]"        

    # Qualify query if ServerName is specified
    if($ServerName)
    {
        $commandText += " WHERE ServerName = '$($ServerName)'"
    }

    # Further qualify query if a database name is specified  
    if($DatabaseName)
    {
        $commandText += " AND DatabaseName = '$($DatabaseName)';"
    }
    else
    {
        # if multiple databases returned order by database 
        $commandText += " ORDER BY ServerName ASC, DatabaseName ASC;"
    }

    $extendedDatabases = @()
    $extendedDatabases += Invoke-SqlAzureWithRetry `
                    -ServerInstance $Catalog.FullyQualifiedServerName `
                    -Database $Catalog.Database.DatabaseName `
                    -Query $commandText `
                    -UserName $config.CatalogAdminUserName `
                    -Password $config.CatalogAdminPassword `
                    -ConnectionTimeout 30 `
                    -QueryTimeout 15 `   
    
    return $extendedDatabases
}


<#
.SYNOPSIS
    Gets extended elastic pool meta data from the catalog
#>
function Get-ExtendedElasticPool{
    param (
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [string]$ServerName,

        [string]$ElasticPoolName
    )

    if ($ElasticPoolName -and -not $ServerName)
    {
        throw "Must specify a ServerName if specifying an ElasticPoolName"
    }

    $config = Get-Configuration

    $commandText = "
        SELECT ServerName, ElasticPoolName, Edition, Dtu, DatabaseDtuMax, DatabaseDtuMin, StorageMB, State, RecoveryState 
        FROM [dbo].[ElasticPools]" 

    # Qualify query if ServerName is specified
    if($ServerName)
    {
        $commandText += " WHERE ServerName = '$($ServerName)'"
    }

    # Further qualify query if an elastic pool name is specified  
    if($ElasticPoolName)
    {
        $commandText += " AND ElasticPoolName = '$($ElasticPoolName)';"
    }
    else
    {
        # if multiple databases returned order by database 
        $commandText += " ORDER BY ServerName ASC, ElasticPoolName ASC;"
    }

    $extendedElasticPools = @()
    $extendedElasticPools += Invoke-SqlAzureWithRetry `
                    -ServerInstance $Catalog.FullyQualifiedServerName `
                    -Database $Catalog.Database.DatabaseName `
                    -Query $commandText `
                    -UserName $config.CatalogAdminUserName `
                    -Password $config.CatalogAdminPassword `
                    -ConnectionTimeout 30 `
                    -QueryTimeout 15 
    
    return $extendedElasticPools
}


<#
.SYNOPSIS
    Gets extended server meta data from the catalog
#>
function Get-ExtendedServer{
    param (
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [string]$ServerName
    )

    $config = Get-Configuration

    $commandText = "SELECT ServerName, State, RecoveryState FROM [dbo].[Servers]" 
    
    if($ServerName)
    {
        $commandText += " WHERE ServerName = '$ServerName';"
    }
    else
    {
        $commandText += " ORDER BY ServerName ASC;"
    }

    $extendedServers = @()
    $extendedServers += Invoke-SqlAzureWithRetry `
                    -ServerInstance $Catalog.FullyQualifiedServerName `
                    -Database $Catalog.Database.DatabaseName `
                    -Query $commandText `
                    -UserName $config.CatalogAdminUserName `
                    -Password $config.CatalogAdminPassword `
                    -ConnectionTimeout 30 `
                    -QueryTimeout 15

    return $extendedServers
}

<#
.SYNOPSIS
    Gets extended tenant meta data from the catalog. If the 'SortTenants' parameter is selected, tenants are returned in priority order from highest priority to lowest priority
#>
function Get-ExtendedTenant 
{
    param (
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$false)]
        [int32]$TenantKey,

        [parameter(Mandatory=$false)]
        [switch]$SortTenants
    )

    $config = Get-Configuration

    $commandText = "SELECT TenantId, TenantName, TenantStatus, ServicePlan, ServerName, DatabaseName, TenantRecoveryState, Location, LastUpdated FROM [dbo].[TenantsExtended]" 
    
    if($TenantKey)
    {
        $tenantHexId = (Get-TenantRawKey -TenantKey $TenantKey).RawKeyHexString
        $commandText += " WHERE TenantId = $tenantHexId;"
    }
    
    $extendedTenants = @()
    $extendedTenants += Invoke-SqlAzureWithRetry `
                            -ServerInstance $Catalog.FullyQualifiedServerName `
                            -Database $Catalog.Database.DatabaseName `
                            -Query $commandText `
                            -UserName $config.CatalogAdminUserName `
                            -Password $config.CatalogAdminPassword `
                            -ConnectionTimeout 30 `
                            -QueryTimeout 15 `

    # Sort tenant list by tenant priority 
    if($SortTenants)
    {
        $tenantPriorityOrder = "Premium", "Standard", "Free"

        $tenantSort = {
            $rank = $tenantPriorityOrder.IndexOf($($_.ServicePlan.ToLower()))
            if ($rank -ne -1) { $rank }
            else { [System.Double]::PositiveInfinity }
        }

        $extendedTenants =  $extendedTenants | sort $tenantSort
    }      
    
    return $extendedTenants
}

<#
.SYNOPSIS
  Validates and normalizes the name for use in creating the tenant key and database name. Removes spaces and sets to lowercase.
#>
function Get-NormalizedTenantName
{
    param
    (
        [parameter(Mandatory=$true)]
        [string]$TenantName
    )

    return $TenantName.Replace(' ','').ToLower()
}


<#
.SYNOPSIS
    Returns a Tenant object for a specific tenant key if registered.
#>
function Get-Tenant
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [string] $TenantName
    )
    $tenantKey = Get-TenantKey -TenantName $TenantName

    try
    {
        $tenantShard = $Catalog.ShardMap.GetMappingForKey($tenantKey)     
    }
    catch
    {
        throw "Tenant '$TenantName' not found in catalog."
    }

    $fullyQualifiedTenantServerName = $tenantShard.Shard.Location.Server
    $tenantServerName = $fullyQualifiedTenantServerName.split('.')[0]
    $tenantDatabaseName = $tenantShard.Shard.Location.Database

    # Find tenant server in Azure 
    $tenantServer = Find-AzureRmResource -ResourceNameEquals $tenantServerName -ResourceType "Microsoft.Sql/servers"

    $tenantDatabase = Get-AzureRmSqlDatabase `
        -ResourceGroupName $tenantServer.ResourceGroupName `
        -ServerName $tenantServerName `
        -DatabaseName $tenantDatabaseName 

    $tenant = New-Object PSObject -Property @{
        Name = $TenantName
        Key = $tenantKey
        Database = $tenantDatabase
    }

    return $tenant            
}

<#
.SYNOPSIS
    Returns an array of all tenants registered in the catalog.
    The returned array contains the TenantName, TenantKey, and ServicePlan of all registered tenants
#>
function Get-Tenants
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog
    )

    $config = Get-Configuration

    $commandText = "SELECT TenantId, TenantName, ServicePlan FROM [dbo].[Tenants]"    
    $tenantList = Invoke-SqlAzureWithRetry `
                    -ServerInstance $Catalog.FullyQualifiedServerName `
                    -Database $Catalog.Database.DatabaseName `
                    -Query $commandText `
                    -UserName $config.CatalogAdminUserName `
                    -Password $config.CatalogAdminPassword `
                    -ConnectionTimeout 30 `
                    -QueryTimeout 15 `

    $registeredTenants = @()
    foreach ($extendedTenant in $tenantList)
    {
        $tenantKey = Get-TenantKey $extendedTenant.TenantName
        $tenant = New-Object PSObject -Property @{
            Name = $extendedTenant.TenantName
            Key = $tenantKey
            ServicePlan = $extendedTenant.ServicePlan
        }

        # store tenant object in array
        $registeredTenants+= $tenant
    }
    return $registeredTenants            
}

<#
.SYNOPSIS
    Returns the service plan of a given tenant
#>
function Get-TenantServicePlan
{
    param (
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$false)]
        [string]$TenantName
    )

    $config = Get-Configuration

    $tenantKey = Get-TenantKey $TenantName
    $tenantHexId = (Get-TenantRawKey -TenantKey $TenantKey).RawKeyHexString
    $commandText = "SELECT ServicePlan FROM [dbo].[TenantsExtended] WHERE TenantId = $tenantHexId" 
    
    $tenantServicePlan = Invoke-SqlAzureWithRetry `
                            -ServerInstance $Catalog.FullyQualifiedServerName `
                            -Database $Catalog.Database.DatabaseName `
                            -Query $commandText `
                            -UserName $config.CatalogAdminUserName `
                            -Password $config.CatalogAdminPassword `
                            -ConnectionTimeout 30 `
                            -QueryTimeout 15 `

    return $tenantServicePlan
}

<#
.SYNOPSIS
    Returns the database that was active for a given tenant at the input time.
#>
function Get-TenantDatabaseForRestorePoint
{
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [int32]$TenantKey,

        [parameter(Mandatory=$true)]
        [DateTime]$RestorePoint
    )

    $restorePointDatabase = $null 
    $tenantMapping = ($Catalog.ShardMap).GetMappingForKey($tenantKey)
    $tenantDatabaseName = $tenantMapping.Shard.Location.Database
    $fullyQualifiedTenantServerName = $tenantMapping.Shard.Location.Server
    $tenantServerName = $fullyQualifiedTenantServerName.split('.')[0]

    # Find tenant server in Azure 
    $tenantServer = Find-AzureRmResource -ResourceNameEquals $tenantServerName -ResourceType "Microsoft.Sql/servers"
    
    # Get active database for tenant 
    $tenantDatabase = Get-AzureRmSqlDatabase `
                        -ResourceGroupName $tenantServer.ResourceGroupName `
                        -ServerName $tenantServerName `
                        -DatabaseName $tenantDatabaseName `
                        -ErrorAction SilentlyContinue

    # Get all deleted databases for tenant 
    $tenantDatabaseList = @()
    $tenantDatabaseList += Get-AzureRmSqlDeletedDatabaseBackup `
                             -ResourceGroupName $Catalog.Database.ResourceGroupName `
                             -ServerName $tenantServerName `
                             -DatabaseName $tenantDatabaseName `
                             -ErrorAction SilentlyContinue

    # Add active database to list of tenant databases if it exists 
    if ($tenantDatabase)
    {
        $tenantDatabaseList += $tenantDatabase 
    }

    # Check all tenant databases to see if they were the active database within the specified time period
    foreach ($database in $tenantDatabaseList)
    {
        # Databases are available for restore 10 minutes after they are created 
        $latestRestorePoint = $null
        $oldestRestorePoint = ($database.CreationDate).AddMinutes(10)
        if ("DeletionDate" -In $database.PSObject.Properties.Name)
        {
            $latestRestorePoint = $database.DeletionDate
        }
       
        # Use current active tenant database if the time period matches
        if (($oldestRestorePoint -lt $RestorePoint) -and (!$latestRestorePoint))
        {
            $restorePointDatabase = $database
            break
        }
        # Use deleted tenant database if the time period matches
        elseif (($oldestRestorePoint -lt $RestorePoint) -and ($latestRestorePoint -gt $RestorePoint))
        {
            $restorePointDatabase = $database
            break
        }
    }

    # Throw error if no database found
    if ($restorePointDatabase -eq $null)
    {
        throw "Tenant database '$tenantDatabaseName' was recently created. `nDatabases must have existed for several minutes before they can be restored. `nWait a few minutes and try again `n "
    }
    else
    {
        return $restorePointDatabase
    }
}


<#
.SYNOPSIS
    Retrieves the server and database name for each database registered in the catalog.
#>
function Get-TenantDatabaseLocations
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog
    )
    # return all databases registered in the catalog shard map
    return Get-Shards -ShardMap $Catalog.ShardMap
}


<#
.SYNOPSIS
    Returns an integer tenant key from a normalized tenant name for use in the catalog.
#>
function Get-TenantKey
{
    param
    (
        # Tenant name 
        [parameter(Mandatory=$true)]
        [String]$TenantName
    )

    $normalizedTenantName = $TenantName.Replace(' ', '').ToLower()

    # Produce utf8 encoding of tenant name 
    $utf8 = New-Object System.Text.UTF8Encoding
    $tenantNameBytes = $utf8.GetBytes($normalizedTenantName)

    # Produce the md5 hash which reduces the size
    $md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    $tenantHashBytes = $md5.ComputeHash($tenantNameBytes)

    # Convert to integer for use as the key in the catalog 
    $tenantKey = [bitconverter]::ToInt32($tenantHashBytes,0)

    return $tenantKey
}


<#
.SYNOPSIS
    Retrieves the venue name from a specified tenant database.
#>
function Get-TenantNameFromTenantDatabase
{
    param(
        [parameter(Mandatory=$true)]
        [string]$TenantServerFullyQualifiedName,

        [parameter(Mandatory=$true)]
        [string]$TenantDatabaseName
    )

    $config = Get-Configuration

    $commandText = "Select Top 1 VenueName from Venue"

    Invoke-SqlAzureWithRetry `
        -ServerInstance $TenantServerFullyQualifiedName `
        -Username $config.TenantAdminuserName `
        -Password $config.TenantAdminPassword `
        -Database $TenantDatabaseName `
        -Query $commandText `
        -ConnectionTimeout 30 `
        -QueryTimeout 30 `
}


<#
.SYNOPSIS
    Returns the raw key used within the shard map for the tenant  Returned as an object containing both the
    byte array and a text representation suitable for insert into SQL.
#>
function Get-TenantRawKey
{
    param
    (
        # Integer tenant key value
        [parameter(Mandatory=$true)]
        [int32]$TenantKey
    )

    # retrieve the byte array 'raw' key from the integer tenant key - the key value used in the catalog database.
    $shardKey = New-Object Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardKey($TenantKey)
    $rawValueBytes = $shardKey.RawValue

    # convert the raw key value to text for insert into the database
    $rawValueString = [BitConverter]::ToString($rawValueBytes)
    $rawValueString = "0x" + $rawValueString.Replace("-", "")

    $tenantRawKey = New-Object PSObject -Property @{
        RawKeyBytes = $rawValueBytes
        RawKeyHexString = $rawValueString
    }

    return $tenantRawKey
}

<#
.SYNOPSIS
    Returns the active tenant server for an input alias. Throws an error if the input alias does not exist
#>
function Get-ServerNameFromAlias
{
    [cmdletbinding()]
    param
    (
        [parameter(Mandatory=$true)]
        [string]$fullyQualifiedTenantAlias
    )

    # Lookup DNS Alias and return the Azure SQL Server to which it's pointing 
    $fullyQualifiedServerName = (Resolve-DnsName $fullyQualifiedTenantAlias -Type CNAME -DnsOnly).NameHost    
    $serverName = $fullyQualifiedServerName.split('.')[0]
    return $serverName
}

<#
.SYNOPSIS
    Initializes a tenant database from a buffer database and registers it in the catalog
#>
function Initialize-TenantFromBufferDatabase
{
    param(
        [Parameter(Mandatory=$true)]
        [object]$Catalog,
        
        [Parameter(Mandatory=$true)]
        [string]$TenantName,

        [Parameter(Mandatory=$false)]
        [string]$VenueType,

        [parameter(Mandatory=$false)]
        [string]$PostalCode,

        [parameter(Mandatory=$false)]
        [string]$CountryCode,

        [Parameter(Mandatory=$false)]
        [object]$BufferDatabase
    )

    $config = Get-Configuration

    # validate tenant name
    $TenantName = $TenantName.Trim()
    Test-LegalName $TenantName > $null

    # validate venue type name
    Test-LegalVenueTypeName $VenueType > $null

    # compute the tenant key from the tenant name, key to be used to register the tenant in the catalog 
    $tenantKey = Get-TenantKey -TenantName $TenantName 

    # check if a tenant with this key is aleady registered in the catalog
    if (Test-TenantKeyInCatalog -Catalog $Catalog -TenantKey $tenantKey)
    {
        throw "A tenant with name '$TenantName' is already registered in the catalog."    
    }
 
    $tenantDatabaseName = Get-NormalizedTenantName -TenantName $TenantName
    $serverName = $BufferDatabase.Name.Split("/",2)[0]
    $sourceDatabase = $BufferDatabase.Name.Split("/",2)[1]

    # rename the buffer database and allocate it to this tenant
    $tenantDatabase = Rename-Database `
                        -SourceDatabaseName $sourceDatabase `
                        -TargetDatabaseName $tenantDatabaseName `
                        -ServerName $serverName

    # initialize the database for the tenant with venue type and other info from the request
    Initialize-TenantDatabase `
            -ServerName $serverName `
            -DatabaseName $tenantDatabaseName `
            -TenantName $TenantName `
            -VenueType $VenueType `
            -PostalCode $PostalCode `
            -CountryCode $CountryCode

    # register the tenant and database in the catalog
    Add-TenantDatabaseToCatalog `
        -Catalog $Catalog `
        -TenantName $TenantName `
        -TenantKey $tenantKey `
        -TenantDatabase $tenantDatabase `
        -TenantServerName $serverName

    return $tenantKey
}


<#
.SYNOPSIS
    Initializes the Venue name and other Venue properties in the database and resets event dates on the
    default events.
#>
function Initialize-TenantDatabase
{
    param(
        [parameter(Mandatory=$true)]
        [string]$ServerName,

        [parameter(Mandatory=$true)]
        [string]$DatabaseName,

        [parameter(Mandatory=$true)]
        [int]$TenantKey,

        [parameter(Mandatory=$true)]
        [string]$TenantName,

        [parameter(Mandatory=$false)]
        [string]$VenueType,

        [parameter(Mandatory=$false)]
        [string]$PostalCode = "98052",

        [parameter(Mandatory=$false)]
        [string]$CountryCode = "USA"

    )

    if ($PostalCode.Length -eq 0) {$PostalCode = "98052"}
    if ($CountryCode.Length -eq 0) {$CountryCode = "USA"}

    $config = Get-Configuration

    if (!$VenueType) {$VenueType = $config.DefaultVenueType}

    # Initialize tenant info in the tenant database (idempotent)
    $emaildomain = (Get-NormalizedTenantName $TenantName)

    if ($emailDomain.Length -gt 40) 
    {
        $emailDomain = $emailDomain.Substring(0,40)
    }

    $VenueAdminEmail = "admin@" + $emailDomain + ".com"

    $commandText = "
        DELETE FROM Venue
        INSERT INTO Venue
            (VenueId, VenueName, VenueType, AdminEmail, PostalCode, CountryCode, Lock  )
        VALUES
            ($TenantKey,'$TenantName', '$VenueType','$VenueAdminEmail', '$PostalCode', '$CountryCode', 'X');
        -- reset event dates for initial default events (these exist and this reset of their dates is done for demo purposes only) 
        EXEC sp_ResetEventDates;"

    Invoke-SqlAzureWithRetry `
        -ServerInstance ($ServerName + ".database.windows.net") `
        -Username $config.TenantAdminuserName `
        -Password $config.TenantAdminPassword `
        -Database $DatabaseName `
        -Query $commandText `

}


<#
.SYNOPSIS
    Invokes a SQL command. Uses ADO.NET not Invoke-SqlCmd. Always uses an encrypted connection.
#>
function Invoke-SqlAzure{
    param
    (
        [Parameter(Mandatory=$true)]
        [string] $ServerInstance,

        [Parameter(Mandatory=$false)]
        [string] $DatabaseName,

        [Parameter(Mandatory=$true)]
        [string] $Query,

        [Parameter(Mandatory=$true)]
        [string] $UserName,

        [Parameter(Mandatory=$true)]
        [string] $Password,

        [Parameter(Mandatory=$false)]
        [int] $ConnectionTimeout = 30,
        
        [Parameter(Mandatory=$false)]
        [int] $QueryTimeout = 60,

        [Parameter(Mandatory=$false)]
        [string] $ApplicationName = 'PowerShell'
      )
    $Query = $Query.Trim()

    $connectionString = `
        "Data Source=$ServerInstance;Initial Catalog=$DatabaseName;Connection Timeout=$ConnectionTimeOut;User ID=$UserName;Password=$Password;Encrypt=true;Application Name=$ApplicationName"

    $connection = new-object system.data.SqlClient.SQLConnection($connectionString)
    $command = new-object system.data.sqlclient.sqlcommand($Query,$connection)
    $command.CommandTimeout = $QueryTimeout

    $connection.Open()

    $reader = $command.ExecuteReader()
    
    $results = @()

    while ($reader.Read())
    {
        $row = @{}
        
        for ($i=0;$i -lt $reader.FieldCount; $i++)
        {
           $row[$reader.GetName($i)]=$reader.GetValue($i)
        }
        $results += New-Object psobject -Property $row
    }
     
    $connection.Close()
    $connection.Dispose()
    
    return $results  
}


<#
.SYNOPSIS
    Wraps Invoke-SqlAzure. Retries on any error with exponential back-off policy.  
    Assumes query is idempotent.  Always uses an encrypted connection.  
#>
function Invoke-SqlAzureWithRetry{
    param(
        [parameter(Mandatory=$true)]
        [string]$DatabaseName,

        [parameter(Mandatory=$true)]
        [string]$ServerInstance,

        [parameter(Mandatory=$true)]
        [string]$Query,

        [parameter(Mandatory=$true)]
        [string]$UserName,

        [parameter(Mandatory=$true)]
        [string]$Password,

        [string]$ConnectionTimeout = 30,

        [int]$QueryTimeout = 30,

        [string]$ApplicationName = 'PowerShell'
    )

    $tries = 1
    $limit = 5
    $interval = 2
    do  
    {
        try
        {
            return Invoke-SqlAzure `
                        -ServerInstance $ServerInstance `
                        -Database $DatabaseName `
                        -Query $Query `
                        -Username $UserName `
                        -Password $Password `
                        -ConnectionTimeout $ConnectionTimeout `
                        -QueryTimeout $QueryTimeout `
                        -ApplicationName $ApplicationName
        }
        catch
        {
                    if ($tries -ge $limit)
                    {
                        throw $_.Exception.Message
                    }                                       
                    Start-Sleep ($interval)
                    $interval += $interval
                    $tries += 1                                      
        }
    }while (1 -eq 1)
}


<#
.SYNOPSIS
    Wraps Invoke-SqlCmd.  Retries on any error with exponential back-off policy.  
    Assumes query is idempotent. Always uses an encrypted connection.
#>
function Invoke-SqlCmdWithRetry{
    param(
        [parameter(Mandatory=$true)]
        [string]$DatabaseName,

        [parameter(Mandatory=$true)]
        [string]$ServerInstance,

        [parameter(Mandatory=$true)]
        [string]$Query,

        [parameter(Mandatory=$true)]
        [string]$UserName,

        [parameter(Mandatory=$true)]
        [string]$Password,

        [string]$ConnectionTimeout = 30,

        [int]$QueryTimeout = 30
    )

    $tries = 1
    $limit = 5
    $interval = 2
    do  
    {
        try
        {
            return Invoke-Sqlcmd `
                        -ServerInstance $ServerInstance `
                        -Database $DatabaseName `
                        -Query $Query `
                        -Username $UserName `
                        -Password $Password `
                        -ConnectionTimeout $ConnectionTimeout `
                        -QueryTimeout $QueryTimeout `
                        -EncryptConnection
        }
        catch
        {
                    if ($tries -ge $limit)
                    {
                        throw $_.Exception.Message
                    }                                       
                    Start-Sleep ($interval)
                    $interval += $interval
                    $tries += 1                                      
        }

    }while (1 -eq 1)
}


<#
.SYNOPSIS
  Provisions a new Wingtip Tickets Platform (WTP) tenant and registers it in the catalog   

.DESCRIPTION
  Creates a new database, imports the WTP tenant bacpac using an ARM template, and initializes 
  venue information.  The tenant database is then in the catalog database.  The tenant
  name is used as the basis of the database name and to generate the tenant key
  used in the catalog.

.PARAMETER WtpResourceGroupName
  The resource group name used during the deployment of the WTP app (case sensitive)

.PARAMETER WtpUser
  The 'User' value that was entered during the deployment of the WTP app

.PARAMETER TenantName
  The name of the tenant being provisioned
#>
function New-Tenant 
{
    Param(
        [Parameter(Mandatory=$true)]
        [string]$WtpResourceGroupName,
    
        [Parameter(Mandatory=$true)]
        [string]$WtpUser,

        [Parameter(Mandatory=$true)]
        [string]$TenantName,

        [Parameter(Mandatory=$true)]
        [string]$ServerName,

        [Parameter(Mandatory=$true)]
        [string]$PoolName,

        [Parameter(Mandatory=$false)]
        [string]$VenueType,

        [Parameter(Mandatory=$false)]
        [string]$PostalCode = "98052",

        [Parameter(Mandatory=$false)]
        [string]$ServicePlan = 'standard'

    )

    $WtpUser = $WtpUser.ToLower()

    $config = Get-Configuration

    $catalog = Get-Catalog -ResourceGroupName $WtpResourceGroupName -WtpUser $WtpUser 

    # Validate tenant name
    $TenantName = $TenantName.Trim()
    Test-LegalName $TenantName > $null
    Test-ValidVenueType $VenueType -Catalog $catalog > $null

    # Compute the tenant key from the tenant name, key to be used to register the tenant in the catalog 
    $tenantKey = Get-TenantKey -TenantName $TenantName 

    # Check if a tenant with this key is aleady registered in the catalog
    if (Test-TenantKeyInCatalog -Catalog $catalog -TenantKey $tenantKey)
    {
        throw "A tenant with name '$TenantName' is already registered in the catalog."    
    }

    # Deploy and initialize a database for this tenant 
    $tenantDatabase = New-TenantDatabase `
        -ResourceGroupName $WtpResourceGroupName `
        -ServerName $ServerName `
        -ElasticPoolName $PoolName `
        -TenantKey $tenantKey `
        -TenantName $TenantName `
        -VenueType $VenueType `
        -PostalCode $PostalCode `
        -WtpUser $WtpUser

    # Register the tenant and database in the catalog
    Add-TenantDatabaseToCatalog -Catalog $catalog `
        -TenantName $TenantName `
        -TenantKey $tenantKey `
        -TenantDatabase $tenantDatabase `
        -TenantServerName $ServerName `
        -TenantServicePlan $ServicePlan

    return $tenantKey
}


<#
.SYNOPSIS
    Creates a tenant database using an ARM template and adds the Venue information.
#>
function New-TenantDatabase
{
    param (
        [parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [parameter(Mandatory=$true)]
        [string]$ServerName,

        [parameter(Mandatory=$true)]
        [string]$ElasticPoolName,

        [parameter(Mandatory=$true)]
        [int]$TenantKey,

        [parameter(Mandatory=$true)]
        [string]$TenantName,

        [parameter(Mandatory=$false)]
        [string]$VenueType,

        [parameter(Mandatory=$false)]
        [string]$PostalCode = '98052',

        [parameter(Mandatory=$false)]
        [string]$CountryCode = 'USA',

        [parameter(Mandatory=$true)]
        [string]$WtpUser
    )

    $config = Get-Configuration

    if(!$VenueType) {$VenueType = $config.DefaultVenueType}

    # Check the tenant server exists
    $Server = Get-AzureRmSqlServer -ResourceGroupName $ResourceGroupName -ServerName $ServerName

    if (!$Server)
    {
        throw "Could not find tenant server '$ServerName'."
    }
    $tenantServerFullyQualifiedName = $ServerName + ".database.windows.net"
    $normalizedTenantName = $TenantName.Replace(' ','').ToLower()

    # Check the tenant database does not exist

    $database = Get-AzureRmSqlDatabase -ResourceGroupName $ResourceGroupName `
        -ServerName $ServerName `
        -DatabaseName $normalizedTenantName `
        -ErrorAction SilentlyContinue

    if ($database)
    {
        throw "Tenant database '$normalizedTenantName' already exists.  Exiting..."
    }

    # create the tenant database
    try
    {
        # A tenant is provisioned by copying a 'golden' tenant database from the catalog server.  
        # An alternative approach could be to deploy an empty database and then import a bacpac into it to initialize it, or to 
        # defer initialization until the tenant is allocated to the database.

        # Construct the resource id for the 'golden' tenant database 
        $AzureContext = Get-AzureRmContext
        $subscriptionId = Get-SubscriptionId
        $catalogAliasName = $config.ActiveCatalogAliasStem + $WtpUser + ".database.windows.net"
        $catalogServerName = Get-ServerNameFromAlias $catalogAliasName
        $SourceDatabaseId = "/subscriptions/$($subscriptionId)/resourcegroups/$ResourceGroupName/providers/Microsoft.Sql/servers/$catalogServerName/databases/$($config.GoldenTenantDatabaseName)"

        # Use an ARM template to create the tenant database by copying the 'golden' database
        $deployment = New-AzureRmResourceGroupDeployment `
            -TemplateFile ($PSScriptRoot + "\" + $config.TenantDatabaseCopyTemplate) `
            -Location $Server.Location `
            -ResourceGroupName $ResourceGroupName `
            -SourceDatabaseId $sourceDatabaseId `
            -ServerName $ServerName `
            -DatabaseName $normalizedTenantName `
            -ElasticPoolName $ElasticPoolName `
            -ErrorAction Stop `
            -Verbose
    }
    catch
    {
        Write-Error $_.Exception.Message
        Write-Error "An error occured deploying the database"
        throw
    }

    #initialize the venue information in the tenant database and reset the default event dates
    Initialize-TenantDatabase `
        -ServerName $ServerName `
        -DatabaseName $normalizedTenantName `
        -TenantKey $TenantKey `
        -TenantName $TenantName `
        -VenueType $VenueType `
        -PostalCode $PostalCode `
        -CountryCode $CountryCode

    # Return the created database
    Get-AzureRmSqlDatabase -ResourceGroupName $ResourceGroupName `
        -ServerName $ServerName `
        -DatabaseName $normalizedTenantName
}


<#
.SYNOPSIS
    Opens tenant-related resources in the portal.
#>
function Open-TenantResourcesInPortal
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [string]$TenantName,

        [parameter(Mandatory=$true)]
        [string[]]$ResourceTypes

    )
    # get the tenant object
    $tenant = Get-Tenant `
        -Catalog $Catalog `
        -TenantName $TenantName

    $subscriptionId = $tenant.Database.ResourceId.Split('/',4)[2]
    $ResourceGroupName = $tenant.Database.ResourceGroupName
    $serverName = $tenant.Database.ServerName
    $databaseName = $tenant.Database.DatabaseName

    if ($ResourceTypes -contains 'server')
    {
        # open the server in the portal
        Start-Process "https://portal.azure.com/#resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Sql/servers/$serverName/overview"
    }

    if ($ResourceTypes -contains 'elasticpool' -and $tenant.Database.CurrentServiceObjectiveName -eq 'ElasticPool')
    {
        $poolName = $tenant.Database.ElasticPoolName

        # open the elastic pool blade in the portal
        Start-Process "https://portal.azure.com/#resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Sql/servers/$serverName/elasticPools/$poolName/overview"
    }

    if ($ResourceTypes -contains 'database')
    {
        # open the database blade in the portal
        Start-Process "https://portal.azure.com/#resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Sql/servers/$serverName/databases/$databaseName/overview"
    }
}


<#
.SYNOPSIS
    Removes tenant info from local shard map
#>
function Remove-CatalogInfoFromTenantDatabase
{
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true)]
        [int32]$TenantKey,

        [parameter(Mandatory=$true)]
        [object]$TenantDatabase

    )

    $config = Get-Configuration
    $adminUserName = $config.TenantAdminUserName
    $adminPassword = $config.TenantAdminPassword
   
    $commandText = "EXECUTE sp_RemoveShardManagement;"

    Invoke-SqlAzureWithRetry `
        -Username $adminUserName `
        -Password $adminPassword `
        -ServerInstance ($TenantDatabase.ServerName + ".database.windows.net") `
        -Database $TenantDatabase.DatabaseName `
        -Query $commandText `
}


<#
.SYNOPSIS
    Deletes extended database metadata from the catalog.
#>
function Remove-ExtendedDatabase
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [string]$ServerName,

        [parameter(Mandatory=$true)]
        [string]$DatabaseName
    )

    $config = Get-Configuration
    $commandText = "
        DELETE FROM Databases 
        WHERE ServerName = '$ServerName' AND DatabaseName = '$DatabaseName';"

    Invoke-SqlAzureWithRetry `
        -ServerInstance $Catalog.FullyQualifiedServerName `
        -Username $config.CatalogAdminuserName `
        -Password $config.CatalogAdminPassword `
        -Database $Catalog.Database.DatabaseName `
        -Query $commandText `
}


<#
.SYNOPSIS
    Removes extended elastic pool entry from catalog  
#>
function Remove-ExtendedElasticPool{
    param (
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [string]$ServerName,

        [parameter(Mandatory=$true)]
        [string]$ElasticPoolName
    )

    $config = Get-Configuration

    $commandText = "
        DELETE FROM [dbo].[ElasticPools]
        WHERE ServerName = '$ServerName' AND ElasticPoolName = '$ElasticPoolName'" 

    Invoke-SqlAzureWithRetry `
        -ServerInstance $Catalog.FullyQualifiedServerName `
        -Database $Catalog.Database.DatabaseName `
        -Query $commandText `
        -UserName $config.CatalogAdminUserName `
        -Password $config.CatalogAdminPassword    
}


<#
.SYNOPSIS
    Deletes an extended server entry from the catalog.
#>
function Remove-ExtendedServer
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [string]$ServerName
    )

    $config = Get-Configuration
    # Delete the database data from the Tenants table
    $commandText = "
        DELETE FROM [dbo].[Servers] 
        WHERE ServerName = '$ServerName'"

    Invoke-SqlAzureWithRetry `
        -ServerInstance $Catalog.FullyQualifiedServerName `
        -Username $config.CatalogAdminuserName `
        -Password $config.CatalogAdminPassword `
        -Database $Catalog.Database.DatabaseName `
        -Query $commandText 
}


<#
.SYNOPSIS
    Removes extended tenant entry from catalog. Additionally removes tenant database entry from databases table  
#>
function Remove-ExtendedTenant
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [int32]$TenantKey,

        [parameter(Mandatory=$true)]
        [string]$ServerName,

        [parameter(Mandatory=$true)]
        [string]$DatabaseName
    )

    $config = Get-Configuration

    # Get the raw tenant key value used within the shard map
    $tenantRawKey = Get-TenantRawKey ($TenantKey)
    $rawkeyHexString = $tenantRawKey.RawKeyHexString


    # Delete the tenant name from the Tenants table
    $commandText = "
        DELETE FROM Tenants 
        WHERE TenantId = $rawkeyHexString;"

    Invoke-SqlAzureWithRetry `
        -ServerInstance $Catalog.FullyQualifiedServerName `
        -Username $config.CatalogAdminuserName `
        -Password $config.CatalogAdminPassword `
        -Database $Catalog.Database.DatabaseName `
        -Query $commandText `

    # Delete the tenant database entry from the Databases table
    $commandText = "
        DELETE FROM Databases 
        WHERE ServerName = '$ServerName' AND DatabaseName = '$DatabaseName';"

    Invoke-SqlAzureWithRetry `
        -ServerInstance $Catalog.FullyQualifiedServerName `
        -Username $config.CatalogAdminuserName `
        -Password $config.CatalogAdminPassword `
        -Database $Catalog.Database.DatabaseName `
        -Query $commandText `
}


<#
.SYNOPSIS
    Removes a tenant, including deleting the database and its associated extended meta data 
    entries from the catalog.
#>
function Remove-Tenant
{
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [int32]$TenantKey,

        [parameter(Mandatory=$false)]
        [switch]$KeepTenantDatabase
    )

    $config = Get-Configuration

    # Take tenant offline
    Set-TenantOffline -Catalog $Catalog -TenantKey $TenantKey

    $tenantMapping = $Catalog.ShardMap.GetMappingForKey($TenantKey)
    $tenantShardLocation = $tenantMapping.Shard.Location
    $fullyQualifiedTenantServerName = $tenantShardLocation.Server
    $tenantServerName = $fullyQualifiedTenantServerName.split('.')[0]

    # Find tenant server in Azure 
    $tenantServer = Find-AzureRmResource -ResourceNameEquals $tenantServerName -ResourceType "Microsoft.Sql/servers"

    # Delete catalog mapping for tenant
    try 
    {
        $Catalog.ShardMap.DeleteMapping($tenantMapping)
    }
    catch 
    {
        # Do nothing if mapping is already deleted 
    }

    # Delete tenant shard from catalog (assumes single database per tenant model)
    try 
    {
        $tenantShard = $Catalog.ShardMap.GetShard($tenantShardLocation)
        $Catalog.ShardMap.DeleteShard($tenantShard)
    }
    catch 
    {
        # Do nothing if shard is already deleted 
    }    

    # Delete tenant database, ignore error if already deleted
    if (!$KeepTenantDatabase)
    {
        Remove-AzureRmSqlDatabase `
            -ResourceGroupName $tenantServer.ResourceGroupName `
            -ServerName $tenantServerName `
            -DatabaseName $tenantShard.Location.Database `
            -ErrorAction Continue `
            >$null  
    }   

    # Remove Tenant entry from Tenants table and corresponding database entry from Databases table
    Remove-ExtendedTenant `
        -Catalog $Catalog `
        -TenantKey $TenantKey `
        -ServerName $fullyQualifiedTenantServerName `
        -DatabaseName $tenantShard.Location.Database    
}


<#
.SYNOPSIS
    This deletes the active database for tenant while leaving the tenant mapping untouched in the catalog.
    This assumes a new database will be created that has the same name, consistent with the mapping in the catalog for this tenant.
#>
function Remove-TenantDatabaseForRestore
{
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [int32]$TenantKey
    )

    # Get active tenant database location
    $deletedTenantDatabase = $null
    $tenantMapping = ($Catalog.ShardMap).GetMappingForKey($TenantKey)
    $tenantDatabaseName = $tenantMapping.Shard.Location.Database
    $fullyQualifiedTenantServerName = $tenantMapping.Shard.Location.Server
    $tenantServerName = $fullyQualifiedTenantServerName.split('.')[0] 

    # Find tenant server in Azure 
    $tenantServer = Find-AzureRmResource -ResourceNameEquals $tenantServerName -ResourceType "Microsoft.Sql/servers"

    $activeTenantDatabase = Get-AzureRmSqlDatabase `
                                -ResourceGroupName $tenantServer.ResourceGroupName `
                                -ServerName $tenantServerName `
                                -DatabaseName $tenantDatabaseName `
                                -ErrorAction SilentlyContinue

    # Delete active tenant database
    if ($activeTenantDatabase)
    {
        $deletedTenantDatabase = Remove-AzureRmSqlDatabase `
                                    -ResourceGroupName $tenantServer.ResourceGroupName `
                                    -ServerName $tenantServerName `
                                    -DatabaseName $tenantDatabaseName `
                                    >$null
    }
    return $deletedTenantDatabase
}


<#
.SYNOPSIS
    Renames a database. Returns when rename is verified complete in ARM. 
#>
function Rename-Database
{
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true)]
        [string]$TargetDatabaseName,

        [parameter(Mandatory=$true)]
        [string]$SourceDatabaseName,

        [parameter(Mandatory=$true)]
        [string]$ServerName
    )

    $config = Get-Configuration

    $commandText = "ALTER DATABASE [$SourceDatabaseName] MODIFY Name = [$TargetDatabaseName];"

    Invoke-SqlAzureWithRetry `
        -Username $config.TenantAdminUserName `
        -Password $config.TenantAdminPassword `
        -ServerInstance ($ServerName + ".database.windows.net") `
        -Database "master" `
        -Query $commandText `

    # Poll to check if database rename is complete and rename has been reflected in ARM
    $databaseRenameComplete = $false
    while (!$databaseRenameComplete)
    {
        try
        {
            # Try to get database with new name, raises error if not available
            $renamedDatabaseObject = Get-AzureRmSqlDatabase `
                                        -ResourceGroupName $Catalog.Database.ResourceGroupName `
                                        -ServerName $tenantServerName `
                                        -DatabaseName $TargetDatabaseName `
                                        >$null                                    

            $databaseRenameComplete = $true
        }
        catch
        {
            # Sleep for 5 seconds before trying again
            Start-Sleep -s 5
        }
    }
    return $renamedDatabaseObject
}


<#
.SYNOPSIS
    Renames a tenant database. If no database object is specified, it will choose the current active tenant database 
#>
function Rename-TenantDatabase
{
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [int32]$TenantKey,

        [parameter(Mandatory=$true)]
        [string]$TargetDatabaseName,

        [parameter(Mandatory=$false)]
        [object]$TenantDatabaseObject = $null
    )

    $config = Get-Configuration
    $adminUserName = $config.CatalogAdminUserName
    $adminPassword = $config.CatalogAdminPassword

    # Get active tenant database location
    $tenantMapping = ($Catalog.ShardMap).GetMappingForKey($TenantKey)
    $tenantDatabaseName = $tenantMapping.Shard.Location.Database
    $fullyQualifiedTenantServerName = $tenantMapping.Shard.Location.Server
    $tenantServerName = $fullyQualifiedTenantServerName.split('.')[0]

    # Find tenant server in Azure 
    $tenantServer = Find-AzureRmResource -ResourceNameEquals $tenantServerName -ResourceType "Microsoft.Sql/servers"

    # Choose active tenant database as database to rename if no database specified 
    if (!$TenantDatabaseObject)
    {
        $TenantDatabaseObject = Get-AzureRmSqlDatabase `
                                -ResourceGroupName $tenantServer.ResourceGroupName `
                                -ServerName $tenantServerName `
                                -DatabaseName $tenantDatabaseName
    }

    # Rename active tenant database using T-SQL on the 'master' database
    Write-Output "Renaming SQL database '$($TenantDatabaseObject.DatabaseName)' to '$TargetDatabaseName'..."

    $renamedDatabaseObject = Rename-Database -SourceDatabaseName $TenantDatabaseObject.DatabaseName -ServerName $tenantServerName -TargetDatabaseName $TargetDatabaseName
       
    return $renamedDatabaseObject
}


<#
.SYNOPSIS
    Creates a DNS alias for an input ServerName. If the 'PollDnsUpdate' switch is specified, the function does not return until the DNS entry has been updated or created 
#>
function Set-DnsAlias
{
    param (
        [parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [parameter(Mandatory=$true)]
        [string]$ServerName,

        [parameter(Mandatory=$true)]
        [string]$ServerDNSAlias,

        [parameter(Mandatory=$false)]
        [string]$OldServerName,

        [parameter(Mandatory=$false)]
        [string]$OldResourceGroupName,

        [parameter(Mandatory=$false)]
        [switch]$PollDnsUpdate
    )

    $fullyQualifiedDNSAlias = $ServerDNSAlias + ".database.windows.net"

    # Check if input alias exists
    $aliasExists = Test-IfDnsAlias $fullyQualifiedDNSAlias 

    # Update alias if it exists already 
    if ($aliasExists)
    {
        $subscriptionId = Get-SubscriptionId
        Set-AzureRmSqlServerDNSAlias `
            -DnsAliasName $ServerDNSAlias `
            -ResourceGroupName $ResourceGroupName `
            -TargetServerName $ServerName `
            -SourceServerResourceGroupName $OldResourceGroupName `
            -SourceServerName $OldServerName `
            -SourceServerSubscriptionId $subscriptionId
    }
    else
    {
        New-AzureRmSqlServerDNSAlias `
            -ResourceGroupName $ResourceGroupName `
            -ServerName $ServerName `
            -DnsAliasName $ServerDNSAlias `
            >$null
    }

    # Poll DNS for changes if requested 
    if ($PollDnsUpdate)
    {
        $requestedServerName = $ServerName 
        $currentServerName = $null
        $elapsedTime = 0
        $timeInterval = 2
        $timeLimit = 150        #Poll for no more than 150 seconds

        while ($currentServerName -ne $requestedServerName)
        {
            try
            {
                $currentServerName = Get-ServerNameFromAlias $fullyQualifiedDNSAlias -ErrorAction SilentlyContinue 2>$null
            
                if (($currentServerName -ne $requestedServerName) -and ($elapsedTime -lt $timeLimit))
                {
                    Write-Verbose "Alias '$ServerDNSAlias' was created but has not fully propagated in DNS. Checking again in $timeInterval seconds..."
                    Start-Sleep $timeInterval
                    $elapsedTime += $timeInterval
                }
                elseif ($elapsedTime -gt $timeLimit)
                {
                    Write-Verbose "Alias '$ServerDNSAlias' was created but has not completed DNS propagation. Exiting..."
                    break
                }   
            }
            catch
            {
                Write-Verbose "Alias '$ServerDNSAlias' was created but has not fully propagated in DNS. Checking again in $timeInterval seconds..."
                Start-Sleep $timeInterval
                $elapsedTime += $timeInterval       
            }           
        }
    }  
}

<#
.SYNOPSIS
    Adds or updates an extended database entry in the catalog
#>
function Set-ExtendedDatabase {
    param (
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [object]$Database,

        [parameter(Mandatory=$false)]
        [String]$RecoveryState='n/a'    
    )
    $config = Get-Configuration

   
    $commandText = "
        MERGE INTO [dbo].[Databases] AS [target]
        USING (VALUES
            ('$($Database.ServerName)', '$($Database.DatabaseName)', '$($Database.CurrentServiceObjectiveName)', '$($Database.ElasticPoolName)', CURRENT_TIMESTAMP))
        AS [source]
            (ServerName, DatabaseName, ServiceObjective, ElasticPoolName, LastUpdated)
        ON target.ServerName = source.ServerName AND target.DatabaseName = source.DatabaseName 
        WHEN MATCHED THEN
            UPDATE SET
                ServiceObjective = source.ServiceObjective,
                ElasticPoolName = source.ElasticPoolName,
                LastUpdated = source.LastUpdated
        WHEN NOT MATCHED THEN
            INSERT (ServerName, DatabaseName, ServiceObjective, ElasticPoolName, State, RecoveryState, LastUpdated)
            VALUES (ServerName, DatabaseName, ServiceObjective, ElasticPoolName,'created', '$RecoveryState', LastUpdated);"    
    
    Invoke-SqlAzureWithRetry `
        -ServerInstance $Catalog.FullyQualifiedServerName `
        -Database $Catalog.Database.DatabaseName `
        -Query $commandText `
        -UserName $config.CatalogAdminUserName `
        -Password $config.CatalogAdminPassword

}


<#
.SYNOPSIS
    Adds or updates an extended elastic pool entry in the catalog
#>
function Set-ExtendedElasticPool{
    param(
    [parameter(Mandatory=$true)]
    [object]$Catalog,

    [parameter(Mandatory=$true)]
    [object]$ElasticPool,

    [parameter(Mandatory=$false)]
    [String]$RecoveryState='n/a' 
    )

    $config = Get-Configuration

    $commandText = "
        MERGE INTO [dbo].[ElasticPools] AS [target]
        USING (VALUES
           ('$($ElasticPool.ServerName)', 
            '$($ElasticPool.ElasticPoolName)', 
            '$($ElasticPool.Edition)',
             $($ElasticPool.Dtu), 
             $($ElasticPool.DatabaseDtuMax),
             $($ElasticPool.DatabaseDtuMin),
             $($ElasticPool.StorageMB),
             CURRENT_TIMESTAMP))
        AS [source]
            (ServerName, ElasticPoolName, Edition, Dtu, DatabaseDtuMax, DatabaseDtuMin, StorageMB, LastUpdated)
        ON target.ServerName = source.ServerName AND target.ElasticPoolName = source.ElasticPoolName 
        WHEN MATCHED THEN
            UPDATE SET
                Edition = source.Edition,
                Dtu = source.Dtu,
                DatabaseDtuMax = source.DatabaseDtuMax,
                DatabaseDtuMin = source.DatabaseDtuMin,
                StorageMB = source.StorageMB,                   
                LastUpdated = source.LastUpdated
        WHEN NOT MATCHED THEN
            INSERT (ServerName, ElasticPoolName, Edition, Dtu, DatabaseDtuMax, DatabaseDtuMin, StorageMB, State, RecoveryState, LastUpdated)
            VALUES (ServerName, ElasticPoolName, Edition, Dtu, DatabaseDtuMax, DatabaseDtuMin, StorageMB, 'created', '$RecoveryState', LastUpdated);"
    
    Invoke-SqlAzureWithRetry `
        -ServerInstance $Catalog.FullyQualifiedServerName `
        -Database $Catalog.Database.DatabaseName `
        -Query $commandText `
        -UserName $config.CatalogAdminUserName `
        -Password $config.CatalogAdminPassword
}


<#
.SYNOPSIS
    Adds an extended server entry to the catalog
#>
function Set-ExtendedServer {
    param (
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [object]$Server,

        [parameter(Mandatory=$false)]
        [String]$RecoveryState='n/a'
    )
 
    $config = Get-Configuration

    $commandText = "
        MERGE INTO [dbo].[Servers] AS [target]
        USING (VALUES
            ('$($Server.ServerName)', '$($Server.Location.Replace(' ','').ToLower())', CURRENT_TIMESTAMP))
        AS [source]
            (ServerName, Location, LastUpdated)
        ON target.ServerName = source.ServerName 
        WHEN NOT MATCHED THEN
            INSERT (ServerName, State, RecoveryState, Location, LastUpdated)
            VALUES (ServerName, 'created', '$RecoveryState', Location, LastUpdated);"
    
    Invoke-SqlAzureWithRetry `
        -ServerInstance $Catalog.FullyQualifiedServerName `
        -Database $Catalog.Database.DatabaseName `
        -Query $commandText `
        -UserName $config.CatalogAdminUserName `
        -Password $config.CatalogAdminPassword
}

<#
.SYNOPSIS
    Adds or updates the recovery checksum of a tenant database
#>
function Set-TenantDatabaseRecoveryChecksum
{
    param(
    [parameter(Mandatory=$true)]
    [object]$Catalog,

    [parameter(Mandatory=$true)]
    [String]$ServerName,

    [parameter(Mandatory=$true)]
    [String]$DatabaseName       
    )

    $config = Get-Configuration
    $commandText = "
    WITH RowVersionSums AS
    (
        SELECT SUM(CAST(Rowversion AS bigint)) AS RowVersionSum from dbo.Customers
        UNION ALL
        SELECT SUM(CAST(Rowversion AS bigint)) from dbo.Events
        UNION ALL
        SELECT SUM(CAST(Rowversion AS bigint)) from dbo.Venue
        UNION ALL
        SELECT SUM(CAST(Rowversion AS bigint)) from dbo.Sections
        UNION ALL
        SELECT SUM(CAST(Rowversion AS bigint)) from dbo.EventSections
        UNION ALL
        SELECT SUM(CAST(Rowversion AS bigint)) from dbo.TicketPurchases
    )
    SELECT SUM(RowVersionSum) AS RecoveryChecksum FROM RowVersionSums;"
    $result =  Invoke-SqlAzureWithRetry `
                    -ServerInstance "$ServerName.database.windows.net" `
                    -Database $DatabaseName `
                    -Query $commandText `
                    -UserName $config.TenantAdminUserName `
                    -Password $config.TenantAdminPassword 
    $recoveryChecksum = $result.RecoveryChecksum     
    
    $commandText = "
    UPDATE [dbo].[Databases]
    SET    RecoveryChecksum = $recoveryChecksum
    WHERE  ServerName = '$ServerName' AND DatabaseName = '$DatabaseName';
    "
    $commandOutput = Invoke-SqlAzureWithRetry `
                        -ServerInstance $Catalog.FullyQualifiedServerName `
                        -Database $Catalog.Database.DatabaseName `
                        -Query $commandText `
                        -Username $config.CatalogAdminUserName `
                        -Password $config.CatalogAdminPassword
}

<#
.SYNOPSIS
    Creates a unique DNS alias that points to the server a tenant's data is stored in
#>
function Set-TenantAlias
{
    param
    (
        [parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory=$true)]
        [string]$WtpUser,

        [parameter(Mandatory=$true)]
        [string]$TenantName,

        [parameter(Mandatory=$true)]
        [string]$TenantServerName       
    )

    $requestedTenantAlias = $null
    $requestedTenantAlias = (Get-NormalizedTenantName $TenantName) + "-" + $WtpUser
    $fullyQualifiedTenantAlias = $requestedTenantAlias + ".database.windows.net"

    # Check if input alias exists
    $aliasExists = Test-IfDnsAlias $fullyQualifiedTenantAlias    
    if ($aliasExists)
    {
        Write-Verbose "An alias already exists for tenant '$TenantName'."
    }    
    else
    {
        # Create new alias if input alias does not exist 
        Set-DnsAlias -ResourceGroupName $ResourceGroupName -ServerName $TenantServerName -ServerDNSAlias $requestedTenantAlias -PollDnsUpdate        
    }    
    return $requestedTenantAlias
}


<#
.SYNOPSIS
    Marks a tenant as offline in the Wingtip tickets tenant catalog
#>
function Set-TenantOffline
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [int32]$TenantKey
    )

    $config = Get-Configuration

    $tenantMapping = ($Catalog.ShardMap).GetMappingForKey($TenantKey)
    $recoveryManager = ($Catalog.ShardMapManager).getRecoveryManager()

    # Detect any differences between local and global shard map -accomodates case where database has been restored while offline
    try
    {
        $shardMapMismatches = $recoveryManager.DetectMappingDifferences($tenantMapping.Shard.Location, $Catalog.ShardMap.Name)

        # Resolve any differences between local and global shard map. Use global shard map as a source of truth if there's a conflict
        foreach ($mismatch in $shardMapMismatches)
        {
            $recoveryManager.ResolveMappingDifferences($mismatch, [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.Recovery.MappingDifferenceResolution]::KeepShardMapMapping)
        }
    }
    catch
    {
        # Continue if the local shards and their shardmap is not available (e.g. for disaster recovery)
    }

    # Mark tenant offline if its mapping status is online, and suppress output
    if ($tenantMapping.Status -eq "Online")
    {
        ($Catalog.ShardMap).MarkMappingOffline($tenantMapping) >$null

        # Update timestamp in catalog
        $tenantHexId = (Get-TenantRawKey -TenantKey $TenantKey).RawKeyHexString
        $commandText = "
            UPDATE [dbo].[Tenants] 
            SET LastUpdated = CURRENT_TIMESTAMP
            WHERE TenantId = $tenantHexId"
    
        Invoke-SqlAzureWithRetry `
            -ServerInstance $Catalog.FullyQualifiedServerName `
            -Database $Catalog.Database.DatabaseName `
            -Query $commandText `
            -UserName $config.CatalogAdminUserName `
            -Password $config.CatalogAdminPassword
    }
}


<#
.SYNOPSIS
    Marks a tenant as online in the Wingtip tickets tenant catalog
#>
function Set-TenantOnline
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [int32]$TenantKey
    )

    $config = Get-Configuration
    $tenantMapping = ($Catalog.ShardMap).GetMappingForKey($TenantKey)
    $recoveryManager = ($Catalog.ShardMapManager).getRecoveryManager()

    # Detect any differences between local and global shard map -accomodates case where database has been restored while offline
    $shardMapMismatches = $recoveryManager.DetectMappingDifferences($tenantMapping.Shard.Location, $Catalog.ShardMap.Name)

    # Resolve any differences between local and global shard map. Use global shard map as a source of truth if there's a conflict
    foreach ($mismatch in $shardMapMismatches)
    {
        $recoveryManager.ResolveMappingDifferences($mismatch, [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.Recovery.MappingDifferenceResolution]::KeepShardMapMapping)
    }

    # Mark tenant online if its mapping status is offline, and suppress output
    if ($tenantMapping.Status -eq "Offline")
    {
       ($Catalog.ShardMap).MarkMappingOnline($tenantMapping) >$null

       # Update timestamp in catalog
        $tenantHexId = (Get-TenantRawKey -TenantKey $TenantKey).RawKeyHexString
        $commandText = "
            UPDATE [dbo].[Tenants] 
            SET LastUpdated = CURRENT_TIMESTAMP
            WHERE TenantId = $tenantHexId"
    
        Invoke-SqlAzureWithRetry `
            -ServerInstance $Catalog.FullyQualifiedServerName `
            -Database $Catalog.Database.DatabaseName `
            -Query $commandText `
            -UserName $config.CatalogAdminUserName `
            -Password $config.CatalogAdminPassword
    }
}

<#
.SYNOPSIS
    Cancels an ongoing or queued restore operation to recover a tenant into the recovery region. 
    If a tenant name is not specified, all ongoing or queued restore operations will be cancelled.
#>
function Stop-TenantRestoreOperations
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$false)]
        [string]$TenantName
    )

    $config = Get-Configuration
    $wtpUser = Get-UserConfig

    # Cancel restore operations for single tenant
    if ($TenantName)
    {
        try
        {
            $tenantKey = Get-TenantKey $TenantName
            $tenantShard = $Catalog.ShardMap.GetMappingForKey($tenantKey)
            $fullyQualifiedTenantServerName = $tenantShard.Shard.Location.Server
            $tenantServerName = $fullyQualifiedTenantServerName.split('.')[0]
            $tenantDatabaseName = $tenantShard.Shard.Location.Database

            # Cancel tenant database restore operations
            $dbState = Update-TenantResourceRecoveryState -Catalog $Catalog -UpdateAction "cancelAndReset" -ServerName $tenantServerName -DatabaseName $tenantDatabaseName

            # Update tenant recovery state
            $tenantState = Update-TenantRecoveryState -Catalog $Catalog -UpdateAction "startReset" -TenantKey $tenantKey
        }
        catch
        {
            throw "Tenant '$TenantName' not found in catalog."
        }
    }
    # Cancel restore operations for all tenants
    else
    {
        # Construct state transition dictionary for resetting state 
        $resourceRecoveryStates = @{'cancelAndReset' = @{"beginState" = ('restoring', 'n/a'); "endState" = ('resetting')} }  
        $requestedState = $resourceRecoveryStates['cancelAndReset'].endState
        $validInitialStates = $resourceRecoveryStates['cancelAndReset'].beginState
        $validInitialStates = "'$($validInitialStates -join "','")'"
        $tenantServerName = $config.TenantServerNameStem + $wtpUser.Name

        $serverNameStem = ($tenantServerName -split "$($config.RecoveryRoleSuffix)")[0]
        $validServerNames = "'$serverNameStem'"

        $cancelRestoreOperationsQuery = "
        UPDATE  [dbo].[Servers] SET
                RecoveryState = '$requestedState',
                LastUpdated = CURRENT_TIMESTAMP
        WHERE   RecoveryState IN ($validInitialStates) AND ServerName IN ($validServerNames);

        UPDATE  [dbo].[ElasticPools] SET
                RecoveryState = '$requestedState',
                LastUpdated = CURRENT_TIMESTAMP
        WHERE   RecoveryState IN ($validInitialStates) AND ServerName IN ($validServerNames);

        UPDATE  [dbo].[Databases] SET
                RecoveryState = '$requestedState',
                LastUpdated = CURRENT_TIMESTAMP
        WHERE   RecoveryState IN ($validInitialStates) AND ServerName IN ($validServerNames);
        " 
   
        $commandOutput = Invoke-SqlAzureWithRetry `
                            -ServerInstance $Catalog.FullyQualifiedServerName `
                            -Database $Catalog.Database.DatabaseName `
                            -Query $cancelRestoreOperationsQuery `
                            -UserName $config.CatalogAdminUserName `
                            -Password $config.CatalogAdminPassword            
    } 
}

<#
.SYNOPSIS
    Checks if the tenant data has been updated. 
    It is primarily used to check if a tenant database should be repatriated back to the primary region during the course of a recovery operation
#>
function Test-IfTenantDataChanged
{
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [string]$TenantName              
    )

    $config = Get-Configuration
    $tenantProperties = Get-ExtendedTenant -Catalog $Catalog -TenantKey (Get-TenantKey $TenantName)

    if (!$tenantProperties.ServerName)
    {
        return $false
    }

    $tenantServerName = $tenantProperties.ServerName.split('.')[0]
    $tenantDatabaseProperties = Get-ExtendedDatabase -Catalog $Catalog -ServerName $tenantServerName -DatabaseName $tenantProperties.DatabaseName
    $recoveryChecksum = $tenantDatabaseProperties.RecoveryChecksum

    # Return false if tenant database has not been recovered
    if ($recoveryChecksum.GetType().Name -eq 'DBNull')
    {
        return $false
    }

    # Retrieve current tenant database rowversion
    $commandText = "
    WITH RowVersionSums AS
    (
        SELECT SUM(CAST(Rowversion AS bigint)) AS RowVersionSum from dbo.Customers
        UNION ALL
        SELECT SUM(CAST(Rowversion AS bigint)) from dbo.Events
        UNION ALL
        SELECT SUM(CAST(Rowversion AS bigint)) from dbo.Venue
        UNION ALL
        SELECT SUM(CAST(Rowversion AS bigint)) from dbo.Sections
        UNION ALL
        SELECT SUM(CAST(Rowversion AS bigint)) from dbo.EventSections
        UNION ALL
        SELECT SUM(CAST(Rowversion AS bigint)) from dbo.TicketPurchases
    )
    SELECT SUM(RowVersionSum) AS RecoveryChecksum FROM RowVersionSums;"
    $result =  Invoke-SqlAzureWithRetry `
                            -ServerInstance $tenantProperties.ServerName `
                            -Database $tenantProperties.DatabaseName `
                            -Query $commandText `
                            -UserName $config.TenantAdminUserName `
                            -Password $config.TenantAdminPassword
    $currChecksum = $result.RecoveryChecksum
    
    if ($currChecksum -eq $recoveryChecksum)
    {
        return $false
    }
    else
    {
        return $true
    }   
}


<#
.SYNOPSIS
    Tests if a tenant key is registered. Returns true if the key exists in the catalog (whether online or offline) or false if it does not.
#>
function Test-TenantKeyInCatalog
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [int32] $TenantKey
    )

    try
    {
        ($Catalog.ShardMap).GetMappingForKey($tenantKey) > $null
        return $true
    }
    catch
    {
        return $false
    }
}


<#
.SYNOPSIS
    Validates a name contains only legal characters
#>
function Test-LegalName
{
    param(
        [parameter(Mandatory=$true)]
        [ValidateScript(
        {
            if ($_ -match '^[A-Za-z0-9][A-Za-z0-9 \-_]*[^\s+]$') 
            {
                $true
            } 
            else 
            {
                throw "'$_' is not an allowed name.  Use a-z, A-Z, 0-9, ' ', '-', or '_'.  Must start with a letter or number and have no trailing spaces."
            }
         }
         )]
        [string]$Input
    )
    return $true
}


<#
.SYNOPSIS
    Validates a name fragment contains only legal characters
#>
function Test-LegalNameFragment
{
    param(
        [parameter(Mandatory=$true)]
        [ValidateScript(
        {
            if ($_ -match '^[A-Za-z0-9 \-_][A-Za-z0-9 \-_]*$') 
            {
                return $true
            } 
            else 
            {
                throw "'$_' is invalid.  Names can only include a-z, A-Z, 0-9, space, hyphen or underscore."
            }
         }
         )]
        [string]$Input
    )
}


<#
.SYNOPSIS
    Validates a venue type name contains only legal characters
#>
function Test-LegalVenueTypeName
{
    param(
        [parameter(Mandatory=$true)]
        [ValidateScript(
        {
            if ($_ -match '^[A-Za-z][A-Za-z]*$') 
            {
                return $true
            } 
            else 
            {
                throw "'$_' is invalid.  Venue type names can only include a-z, A-Z."
            }
         }
         )]
        [string]$Input
    )
}


<#
.SYNOPSIS
    Validates that a venue type is a supported venue type (validated against the  
    golden tenant database on the catalog server)
#>
function Test-ValidVenueType
{
    param(
        [parameter(Mandatory=$true)]
        [string]$VenueType,

        [parameter(Mandatory=$true)]
        [object]$Catalog
    )
    $config = Get-Configuration

    $commandText = "
        SELECT Count(VenueType) AS Count FROM [dbo].[VenueTypes]
        WHERE VenueType = '$VenueType'"

    $results = Invoke-SqlAzureWithRetry `
                    -ServerInstance $Catalog.FullyQualifiedServerName `
                    -Username $config.CatalogAdminuserName `
                    -Password $config.CatalogAdminPassword `
                    -Database $config.GoldenTenantDatabaseName `
                    -Query $commandText

    if($results.Count -ne 1)
    {
        throw "Error: '$VenueType' is not a supported venue type."
    }

    return $true
}

<#
.SYNOPSIS
    Validates that an input DNS alias exists. Returns true if the alias exists, false otherwise
#>
function Test-IfDnsAlias
{
    param(
        [parameter(Mandatory=$true)]
        [string]$fullyQualifiedAliasName
    )

    # Retrieve the servername for input alias if it exists
    try
    {
        $tenantServer = Get-ServerNameFromAlias $fullyQualifiedAliasName
        return $true
    }
    catch
    {
        return $false
    } 
}

<#
.SYNOPSIS
    Update service plan of a tenant
#>
function Update-TenantServicePlan
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [string]$TenantName,
       
        [parameter(Mandatory=$true)]
        [string]$RequestedTenantServicePlan        
    )

    $config = Get-Configuration
    $tenantObject = Get-Tenant -Catalog $Catalog -TenantName $TenantName    
    $tenantHexId = (Get-TenantRawKey -TenantKey $tenantObject.Key).RawKeyHexString        
    $commandText = "
        UPDATE [dbo].[Tenants] 
        SET ServicePlan = '$RequestedTenantServicePlan', LastUpdated = CURRENT_TIMESTAMP
        WHERE TenantId = $tenantHexId"
    
    $result = Invoke-SqlAzureWithRetry `
                -ServerInstance $Catalog.FullyQualifiedServerName `
                -Database $Catalog.Database.DatabaseName `
                -Query $commandText `
                -UserName $config.CatalogAdminUserName `
                -Password $config.CatalogAdminPassword

    return $result    
}

<#
.SYNOPSIS
    Update servername and/or databasename stored in the catalog for a tenant. 
    This is particularly useful after disaster recovery when the identity of a tenant database has changed to a recovery instance.
#>
function Update-TenantShardInfo
{
    param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [string]$TenantName,

        [parameter(Mandatory=$true)]
        [string]$FullyQualifiedTenantServerName,

        [parameter(Mandatory=$true)]
        [string]$TenantDatabaseName        
    )

    $config = Get-Configuration
    $tenantKey = Get-TenantKey $TenantName
    $recoveryManager = ($Catalog.ShardMapManager).getRecoveryManager()

    if ($recoveryManager)
    {
        try
        {
            $tenantMapping = $Catalog.ShardMap.GetMappingForKey($tenantKey)
            $tenantShard = $tenantMapping.Shard
            $tenantShardLocation = $tenantShard.Location
            $tenantServer = $tenantShardLocation.Server

            if (($tenantServer -ne $FullyQualifiedTenantServerName) -or ($tenantShardLocation.Database -ne $TenantDatabaseName))
            {
                $recoveryShardLocation = New-Object Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardLocation($FullyQualifiedTenantServerName, $TenantDatabaseName, 'tcp', '1433')
                if ($recoveryShardLocation)
                {
                    $recoveryManager.DetachShard($tenantShardLocation)
                    $recoveryManager.AttachShard($recoveryShardLocation)

                    $mappingDifferences = $recoveryManager.DetectMappingDifferences($recoveryShardLocation)
                    foreach ($diff in $mappingDifferences)
                    {
                        $recoveryManager.ResolveMappingDifferences($diff, [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.Recovery.MappingDifferenceResolution]::KeepShardMapping)
                    }
                }               
            }    
        }
        catch [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardManagementException]
        {
            # Tenant mapping does not exist in global shard map
            $mappingErrorMessage = "Mapping containing the given key value could not be located in the shard map"
            if ($_.Exception.Message -match $mappingErrorMessage)
            {
                $recoveryShardLocation = New-Object Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardLocation($FullyQualifiedTenantServerName, $TenantDatabaseName, 'tcp', '1433')
                if ($recoveryShardLocation)
                {
                    if ($recoveryManager)
                    {
                        $recoveryManager.AttachShard($recoveryShardLocation)  
                    }
                    else
                    {
                        $recoveryManager = ($Catalog.ShardMapManager).getRecoveryManager()
                        $recoveryManager.AttachShard($recoveryShardLocation)  
                    }

                    $mappingDifferences = $recoveryManager.DetectMappingDifferences($recoveryShardLocation)
                    foreach ($diff in $mappingDifferences)
                    {
                        $recoveryManager.ResolveMappingDifferences($diff, [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.Recovery.MappingDifferenceResolution]::KeepShardMapping)
                    }
                }               
            }
            else
            {
                throw $_.Exception.Message    
            }
            
        }    
        catch
        {
            throw $_.Exception.Message
        }
        return $true
    }
    else
    {
        return $false       
    }   
}

<#
.SYNOPSIS
    Updates the recovery state of an input tenant. This function returns the previous recovery state, and the updated recovery state if the update was successful
#>
function Update-TenantRecoveryState
{
    param (
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [validateset('startRecovery', 'endRecovery', 'startShardUpdateToRecovery', 'endShardUpdateToRecovery', 'startReset', 'endReset', 'startRepatriation', 'endRepatriation', 'startShardUpdateToOrigin', 'endShardUpdateToOrigin')]
        [string]$UpdateAction,

        [parameter(Mandatory=$true)]
        [int32]$TenantKey
    )
 
    $config = Get-Configuration
    $tenantHexId = (Get-TenantRawKey -TenantKey $TenantKey).RawKeyHexString

    <# Recovery states for tenants

        Initial State                   |   End State                       |   TransitionName
        =================================================================================================
        n/a                             |   RestoringTenantData             |   startRecovery               (start recovery operations for tenant resources)
        OnlineInOrigin                  |   RestoringTenantData             |   startRecovery               (start recovery operations for tenant resources)
        -------------------------------------------------------------------------------------------------
        RestoringTenantData             |   ResettingTenantToOrigin         |   startReset                  (reset tenant resources back to origin)
        RestoredTenantData              |   ResettingTenantToOrigin         |   startReset                  (reset tenant resources back to origin)
        UpdatingTenantShardToRecovery   |   ResettingTenantToOrigin         |   startReset                  (reset tenant resources back to origin)
        OnlineInRecovery                |   ResettingTenantToOrigin         |   startReset                  (reset tenant resources back to origin)
        ResettingTenantToOrigin         |   OnlineInOrigin                  |   endReset                    (tenant resources successfully reset back to origin)
        --------------------------------------------------------------------------------------------------
        n/a                             |   RestoredTenantData              |   endRecovery                 (tenant resources successfully restored in recovery region)
        RestoringTenantData             |   RestoredTenantData              |   endRecovery                 (tenant resources successfully restored in recovery region)
        RestoredTenantData              |   UpdatingTenantShardToRecovery   |   startShardUpdateToRecovery  (update tenant shard details to bring tenant online in recovery region)
        UpdatingTenantShardToRecovery   |   OnlineInRecovery                |   endShardUpdateToRecovery    (tenant shard update successful and tenant is online in recovery region)
        --------------------------------------------------------------------------------------------------
        n/a                             |   RepatriatingTenantData          |   startRepatriation           (tenant resources in the process of migrating back to origin)       
        OnlineInRecovery                |   RepatriatingTenantData          |   startRepatriation           (tenant resources in the process of migrating back to origin)
        RepatriatingTenantData          |   RepatriatedTenantData           |   endRepatriation             (tenant resources successfully migrated back to origin)
        --------------------------------------------------------------------------------------------------
        RepatriatedTenantData           |   UpdatingTenantShardToOrigin     |   startShardUpdateToOrigin    (update tenant shard details to bring tenant online in origin region)
        UpdatingTenantShardToOrigin     |   OnlineInOrigin                  |   endShardUpdateToOrigin      (tenant shard update successful and tenant is back online in origin region)
    #>
    
    # Construct state transition dictionary for tenant object 
    $tenantRecoveryStates = @{
        'startRecovery' = @{ "beginState" = ('n/a', 'OnlineInOrigin'); "endState" = ('RestoringTenantData') };
        'startReset' = @{ "beginState" = ('RestoringTenantData', 'RestoredTenantData', 'UpdatingTenantShardToRecovery', 'OnlineInRecovery'); "endState" = ('ResettingTenantToOrigin') };
        'endReset' = @{ "beginState" = ('ResettingTenantToOrigin'); "endState" = ('OnlineInOrigin') };
        'endRecovery' = @{ "beginState" = ('RestoringTenantData', 'n/a'); "endState" = ('RestoredTenantData') };
        'startShardUpdateToRecovery' = @{ "beginState" = ('RestoredTenantData'); "endState" = ('UpdatingTenantShardToRecovery')};
        'endShardUpdateToRecovery' = @{ "beginState" = ('UpdatingTenantShardToRecovery'); "endState" = "OnlineInRecovery"};
        'startRepatriation' = @{ "beginState" = ('OnlineInRecovery', 'n/a'); "endState" = ('RepatriatingTenantData') };        
        'endRepatriation' = @{ "beginState" = ('RepatriatingTenantData'); "endState" = ('RepatriatedTenantData') };
        'startShardUpdateToOrigin' = @{ "beginState" = ('RepatriatedTenantData'); "endState" = ('UpdatingTenantShardToOrigin')};
        'endShardUpdateToOrigin' = @{ "beginState" = ('UpdatingTenantShardToOrigin'); "endState" = ('OnlineInOrigin')};
    }    

    $requestedState = $tenantRecoveryStates[$UpdateAction].endState
    $validInitialStates = $tenantRecoveryStates[$UpdateAction].beginState
    $validInitialStates = "'$($validInitialStates -join "','")'"

    $commandText = "
        UPDATE  [dbo].[Tenants] SET
                RecoveryState = '$requestedState',
                LastUpdated = CURRENT_TIMESTAMP
        OUTPUT 
                inserted.RecoveryState AS recoveryState,
                deleted.RecoveryState AS oldRecoveryState,
                inserted.LastUpdated AS updateTime
        WHERE   TenantId = $tenantHexId AND RecoveryState IN ($validInitialStates)
        "

    $commandOutput = Invoke-SqlAzureWithRetry `
                        -ServerInstance $Catalog.FullyQualifiedServerName `
                        -Database $Catalog.Database.DatabaseName `
                        -Query $commandText `
                        -UserName $config.CatalogAdminUserName `
                        -Password $config.CatalogAdminPassword

    return $commandOutput
}

<#
.SYNOPSIS
    Updates the recovery state of a tenant's server, database, or elastic pool. This function returns the previous recovery state, and the updated recovery state if the update was successful
#>
function Update-TenantResourceRecoveryState
{
    param (
        [parameter(Mandatory=$true)]
        [object]$Catalog,

        [parameter(Mandatory=$true)]
        [validateset('startRecovery', 'startFailover', 'endFailover', 'cancelAndReset', 'endRecovery', 'startReset', 'endReset', 'startReplication', 'endReplication', 'startFailback', 'conclude', 'markError')]
        [string]$UpdateAction,

        [parameter(Mandatory=$true)]
        [string]$ServerName, 

        [parameter(Mandatory=$false)]
        [string]$ElasticPoolName, 

        [parameter(Mandatory=$false)]
        [string]$DatabaseName 
    )

    <# Recovery states for databases, elastic pools, and servers

        Initial State           |   End State           |   TransitionName
        ==========================================================================
        n/a                     |   restoring           |   startRecovery      (start recovery operations) 
        n/a                     |   failingOver         |   startFailover      (start failover operations)
        complete                |   restoring           |   startRecovery      (start recovery operations)
        complete                |   failingOver         |   startFailover      (start failover operations)
        errorState              |   restoring           |   startRecovery      (restart recovery operations)
        errorState              |   failingOver         |   startFailover      (restart failover operations)
        --------------------------------------------------------------------------
        restoring               |   resetting           |   cancelAndReset     (reset back to origin if region comes back online during recovery operations)
        n/a                     |   resetting           |   cancelAndReset     (reset back to origin if region comes back online during recovery operations)       
        n/a                     |   resetting           |   startReset         (reset back to origin if data in recovery region is identical to origin region)                
        restored                |   resetting           |   startReset         (reset back to origin if data in recovery region is identical to origin region)        
        errorState              |   resetting           |   startReset         (reset back to origin if data in recovery region is identical to origin region)
        resetting               |   complete            |   endReset           (reset operations successfully completed)
        resetting               |   errorState          |   markError          (reset operations failed)
        --------------------------------------------------------------------------
        restoring               |   restored            |   endRecovery        (recovery operations successfully completed)
        complete                |   restored            |   endRecovery        (recovery operations successfully completed)
        failingOver             |   failedOver          |   endFailover        (failover operations successfully completed)
        restoring               |   errorState          |   markError          (recovery operations failed)
        failingOver             |   errorState          |   markError          (failover operations failed)
        --------------------------------------------------------------------------
        n/a                     |   replicating         |   startReplication   (replicate changed data to origin)
        restored                |   replicating         |   startReplication   (replicate changed data to origin)
        errorState              |   replicating         |   startReplication   (replicate changed data to origin)
        replicating             |   replicated          |   endReplication     (replication to origin successfully completed)
        replicating             |   errorState          |   markError          (replication to origin failed)
        --------------------------------------------------------------------------
        n/a                     |   repatriating        |   startFailback      (failback to origin)
        replicated              |   repatriating        |   startFailback      (failback to origin)
        failedOver              |   repatriating        |   startFailback      (failback to origin)
        markError               |   repatriating        |   startFailback      (failback to origin)
        repatriating            |   complete            |   conclude           (failback to origin successfully completed)
        repatriating            |   errorState          |   markError          (failback to origin failed)
    #>


    $config = Get-Configuration
   
    # Construct state transition dictionary for tenant object 
    $resourceRecoveryStates = @{
        'startRecovery' = @{ "beginState" = ('n/a', 'complete', 'errorState'); "endState" = ('restoring') };
        'startFailover' = @{ "beginState" = ('n/a', 'complete', 'errorState'); "endState" = ('failingOver') };
        'cancelAndReset' = @{ "beginState" = ('restoring', 'n/a'); "endState" = ('resetting') };
        'startReset' = @{ "beginState" = ('n/a','restored', 'errorState'); "endState" = ('resetting') };
        'endReset' = @{ "beginState" = ('resetting'); "endState" = ('complete') };
        'markError' = @{ "beginState" = ('n/a','restoring', 'resetting', 'failingOver', 'replicating', 'repatriating'); "endState" = ('errorState')};
        'endRecovery' = @{ "beginState" = ('restoring','complete'); "endState" = ('restored') };
        'endFailover' = @{ "beginState" = ('failingOver'); "endState" = ('failedOver') };        
        'startReplication' = @{ "beginState" = ('restored', 'errorState', 'n/a'); "endState" = ('replicating') };
        'endReplication' = @{ "beginState" = ('replicating'); "endState" = ('replicated') };
        'startFailback' = @{ "beginState" = ('n/a','replicated', 'failedOver', 'errorState'); "endState" = ('repatriating') };
        'conclude' = @{ "beginState" = ('repatriating'); "endState" = ('complete') };
    }    

    $requestedState = $resourceRecoveryStates[$UpdateAction].endState
    $validInitialStates = $resourceRecoveryStates[$UpdateAction].beginState
    $validInitialStates = "'$($validInitialStates -join "','")'"

    # Update recovery states of both origin and recovery instances of tenant resources if applicable
    $serverNameStem = ($ServerName -split "$($config.RecoveryRoleSuffix)")[0]
    $validServerNames = "'$serverNameStem','$serverNameStem$($config.RecoveryRoleSuffix)'"

    if ($DatabaseName)
    {
        $commandText = "
        UPDATE  [dbo].[Databases] SET
                RecoveryState = '$requestedState',
                LastUpdated = CURRENT_TIMESTAMP
        OUTPUT 
                inserted.RecoveryState AS recoveryState,
                deleted.RecoveryState AS oldRecoveryState,
                inserted.LastUpdated AS updateTime
        WHERE   ServerName IN ($validServerNames) AND DatabaseName = '$DatabaseName' AND RecoveryState IN ($validInitialStates)
        "
    }
    # Elastic pools cannot be failed over
    elseif ($ElasticPoolName -and ($UpdateAction -ne 'startFailover'))
    {
        $commandText = "
        UPDATE  [dbo].[ElasticPools] SET
                RecoveryState = '$requestedState',
                LastUpdated = CURRENT_TIMESTAMP
        OUTPUT 
                inserted.RecoveryState AS recoveryState,
                deleted.RecoveryState AS oldRecoveryState,
                inserted.LastUpdated AS updateTime
        WHERE   ServerName IN ($validServerNames) AND ElasticPoolName = '$ElasticPoolName' AND RecoveryState IN ($validInitialStates)
        "
    }
    # Servers cannot be failed over
    elseif ($ServerName -and ($UpdateAction -ne 'startFailover'))
    {
        $commandText = "
        UPDATE  [dbo].[Servers] SET
                RecoveryState = '$requestedState',
                LastUpdated = CURRENT_TIMESTAMP
        OUTPUT 
                inserted.RecoveryState AS recoveryState,
                deleted.RecoveryState AS oldRecoveryState,
                inserted.LastUpdated AS updateTime
        WHERE   ServerName IN ($validServerNames) AND RecoveryState IN ($validInitialStates)
        "
    }
    
    $commandOutput = Invoke-SqlAzureWithRetry `
                        -ServerInstance $Catalog.FullyQualifiedServerName `
                        -Database $Catalog.Database.DatabaseName `
                        -Query $commandText `
                        -UserName $config.CatalogAdminUserName `
                        -Password $config.CatalogAdminPassword

    return $commandOutput
}