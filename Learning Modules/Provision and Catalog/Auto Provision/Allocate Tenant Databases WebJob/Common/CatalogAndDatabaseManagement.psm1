<#
.Synopsis
  This module implements a tenant-focused catalog and database API over the Shard Management APIs. 
  It simplifies catalog management by focusing on operations done to a tenant and tenant databases.
#>

Import-Module $PSScriptRoot\..\WtpConfig -Force
Import-Module $PSScriptRoot\..\ProvisionConfig -Force
Import-Module $PSScriptRoot\AzureShardManagement -Force
Import-Module sqlserver -ErrorAction SilentlyContinue

# Stop execution on error
$ErrorActionPreference = "Stop"


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
        [string]$TenantName
    )

    $config = Get-Configuration

    # Get the raw tenant key value used within the shard map
    $tenantRawKey = Get-TenantRawKey ($TenantKey)
    $rawkeyHexString = $tenantRawKey.RawKeyHexString


    # Add the tenant name into the Tenants table
    $commandText = "
        MERGE INTO Tenants as [target]
        USING (VALUES ($rawkeyHexString, '$TenantName')) AS source
            (TenantId, TenantName)
        ON target.TenantId = source.TenantId
        WHEN MATCHED THEN
            UPDATE SET TenantName = source.TenantName
        WHEN NOT MATCHED THEN
            INSERT (TenantId, TenantName)
            VALUES (source.TenantId, source.TenantName);"

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
    Registers a tenant database in the catalog, including adding the tenant name as extended tenant meta data.
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
        [object]$TenantDatabase
    )

    $tenantServerFullyQualifiedName = $TenantDatabase.ServerName + ".database.windows.net"

    # Add the database to the catalog shard map (idempotent)
    Add-Shard -ShardMap $Catalog.ShardMap `
        -SqlServerName $tenantServerFullyQualifiedName `
        -SqlDatabaseName $TenantDatabase.DatabaseName

    # Add the tenant-to-database mapping to the catalog (idempotent)
    Add-ListMapping `
        -KeyType $([int]) `
        -ListShardMap $Catalog.ShardMap `
        -SqlServerName $tenantServerFullyQualifiedName `
        -SqlDatabaseName $TenantDatabase.DatabaseName `
        -ListPoint $TenantKey

    # Add the tenant name to the catalog as extended meta data (idempotent)
    Add-ExtendedTenantMetaDataToCatalog `
        -Catalog $Catalog `
        -TenantKey $TenantKey `
        -TenantName $TenantName
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
    Initializes and returns a catalog object based on the catalog database created during deployment of the
    WTP application.  The catalog contains the initialized shard map manager and shard map, which can be used to access
    the associated databases (shards) and tenant key mappings.
#>
function Get-Catalog
{
    param (
        [parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [parameter(Mandatory=$true)]
        [string]$WtpUser
    )
    $config = Get-Configuration

    $catalogServerName = $config.CatalogServerNameStem + $WtpUser
    $catalogServerFullyQualifiedName = $catalogServerName + ".database.windows.net"

    # Check catalog database exists
    $catalogDatabase = Get-AzureRmSqlDatabase `
        -ResourceGroupName $ResourceGroupName `
        -ServerName $catalogServerName `
        -DatabaseName $config.CatalogDatabaseName `
        -ErrorAction Stop

    # Initialize shard map manager from catalog database
    [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManager]$shardMapManager = Get-ShardMapManager `
        -SqlServerName $catalogServerFullyQualifiedName `
        -UserName $config.CatalogAdminUserName `
        -Password $config.CatalogAdminPassword `
        -SqlDatabaseName $config.CatalogDatabaseName

    if (!$shardmapManager)
    {
        throw "Failed to initialize shard map manager from '$(config.CatalogDatabaseName)' database. Ensure catalog is initialized by opening the Events app and try again."
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
            FullyQualifiedServerName = $catalogServerFullyQualifiedName
            Database = $catalogDatabase
            }

        return $catalog
    }
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
    $tenantServerName = ($tenantMapping.Shard.Location.Server).Split('.')[0]

    # Get active tenant database 
    $activeTenantDatabase = Get-AzureRmSqlDatabase `
                                -ResourceGroupName $Catalog.database.ResourceGroupName `
                                -ServerName $tenantServerName `
                                -DatabaseName $tenantDatabaseName `
                                -ErrorAction SilentlyContinue

    # Get restored tenant database 
    $restoredTenantDatabase = Get-AzureRmSqlDatabase `
                                -ResourceGroupName $Catalog.database.ResourceGroupName `
                                -ServerName $tenantServerName `
                                -DatabaseName $tenantDatabaseName + "_old" `
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

    $commandText = "SELECT DatabaseName, ServiceObjective, ElasticPoolName, State FROM [dbo].[Databases]"        

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
        SELECT ServerName, ElasticPoolName, Edition, Dtu, DatabaseDtuMax, DatabaseDtuMin, StorageMB, DatabasesMax, BufferDatabases, State 
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

    $commandText = "SELECT ServerName, State FROM [dbo].[Servers]" 
    
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
                    -QueryTimeout 15 `      
    
    return $extendedServers
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

    $tenantServerName = $tenantShard.Shard.Location.Server.Split('.',2)[0]
    $tenantDatabaseName = $tenantShard.Shard.Location.Database

    # requires tenant resource group is same as catalog resource group
    $TenantResourceGroupName = $Catalog.Database.ResourceGroupName
     
    $tenantDatabase = Get-AzureRmSqlDatabase `
        -ResourceGroupName $TenantResourceGroupName `
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
    $tenantServerName = ($tenantMapping.Shard.Location.Server).Split('.')[0]
    
    # Get active database for tenant 
    $tenantDatabase = Get-AzureRmSqlDatabase `
                        -ResourceGroupName $Catalog.Database.ResourceGroupName `
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
        $oldestRestorePoint = ($database.CreationDate).AddMinutes(10)
        $latestRestorePoint = $database.DeletionDate

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
        throw "No tenant databases were found that were active at the specified restore point."
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
        RawKeyBytes = $shardKeyRawValueBytes
        RawKeyHexString = $rawValueString
    }

    return $tenantRawKey
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
    if (Test-TenantKeyInCatalog -Catalog $catalog -TenantKey $tenantKey)
    {
        throw "A tenant with name '$TenantName' is already registered in the catalog."    
    }
 
    $tenantDatabaseName = Get-NormalizedTenantName -TenantName $TenantName
    $serverName = $BufferDatabase.Name.Split("/",2)[0]

    # rename the buffer database and allocate it to this tenant
    $tenantDatabase = Rename-Database `
                        -SourceDatabase $BufferDatabase `
                        -TargetDatabaseName $tenantDatabaseName

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
        -Catalog $catalog `
        -TenantName $TenantName `
        -TenantKey $tenantKey `
        -TenantDatabase $tenantDatabase `

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
            (VenueName, VenueType, AdminEmail, PostalCode, CountryCode, Lock  )
        VALUES
            ('$TenantName', '$VenueType','$VenueAdminEmail', '$PostalCode', '$CountryCode', 'X');
        -- reset event dates for initial default events (these exist and this reset of their dates is done for demo purposes only) 
        EXEC sp_ResetEventDates;"

    Invoke-SqlAzureWithRetry `
        -ServerInstance ($ServerName + ".database.windows.net") `
        -Username $config.TenantAdminuserName `
        -Password $config.TenantAdminPassword `
        -Database $DatabaseName `
        -Query $commandText `
        -ConnectionTimeout 30 `
        -QueryTimeout 30 `
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
        [int] $QueryTimeout = 60
      )
    $Query = $Query.Trim()

    $connectionString = `
        "Data Source=$ServerInstance;Initial Catalog=$DatabaseName;Connection Timeout=$ConnectionTimeOut;User ID=$UserName;Password=$Password;Encrypt=true;"

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

        [int]$QueryTimeout = 30
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
        [string]$VenueType
    )

    $WtpUser = $WtpUser.ToLower()

    $config = Get-Configuration

    $catalog = Get-Catalog -ResourceGroupName $WtpResourceGroupName -WtpUser $WtpUser 

    # Validate tenant name
    $TenantName = $TenantName.Trim()
    Test-LegalName $TenantName > $null
    Test-LegalVenueTypeName $VenueType > $null

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
        -TenantName $TenantName `
        -VenueType $VenueType `
        -WtpUser $WtpUser

    # Register the tenant and database in the catalog
    Add-TenantDatabaseToCatalog -Catalog $catalog `
        -TenantName $TenantName `
        -TenantKey $tenantKey `
        -TenantDatabase $tenantDatabase `

    return $tenantKey
}


<#
.SYNOPSIS
    Creates a tenant database using an ARM template and updates the Venue information with the default VenueType.
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
        # Deployment in WTP is by copying a 'golden' tenant database on the catalog server.  
        # An alternative approach could be to deploy an empty database and then import a bacpac into it to initialize it, or to 
        # defer initialization until the tenant is allocated to the database.

        # Construct the resource id for the 'golden' tenant database 
        $AzureContext = Get-AzureRmContext
        $SourceDatabaseId = "/subscriptions/$($AzureContext.Subscription.SubscriptionId)/resourcegroups/$ResourceGroupName/providers/Microsoft.Sql/servers/$($config.CatalogServerNameStem)$WtpUser/databases/$($config.GoldenTenantDatabaseName)"

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
        -ConnectionTimeout 30 `
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
        [string]$DatabaseName
    )

    $commandText = "
        DELETE FROM Databases 
        WHERE DatabaseName = $DatabaseName;"

    Invoke-SqlAzureWithRetry `
        -ServerInstance $Catalog.FullyQualifiedServerName `
        -Username $config.CatalogAdminuserName `
        -Password $config.CatalogAdminPassword `
        -Database $Catalog.Database.DatabaseName `
        -Query $commandText `
        -ConnectionTimeout 30 `
        -QueryTimeout 30 `
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
        -Password $config.CatalogAdminPassword `
        -ConnectionTimeout 30 `
        -QueryTimeout 15     
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
    Removes extended tenant and associated database meta data entries from catalog  
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
        WHERE TenantId = $rawkeyHexString;
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
        [int32]$TenantKey
    )

    # Take tenant offline
    Set-TenantOffline -Catalog $Catalog -TenantKey $TenantKey

    $tenantMapping = $Catalog.ShardMap.GetMappingForKey($TenantKey)
    $tenantShardLocation = $tenantMapping.Shard.Location

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

    # Delete tenant database, ignore error if alread deleted
    Remove-AzureRmSqlDatabase -ResourceGroupName $Catalog.Database.ResourceGroupName `
        -ServerName ($tenantShard.Location.Server).Split('.')[0] `
        -DatabaseName $tenantShard.Location.Database `
        -ErrorAction Continue `
        >$null

    # Remove Tenant entry from Tenants table and corresponding database entry from Databases table
    Remove-ExtendedTenantMetadataFromCatalog `
        -Catalog $Catalog `
        -TenantKey $TenantKey `
        -ServerName ($tenantShard.Location.Server).Split('.')[0] `
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
    $tenantServerName = ($tenantMapping.Shard.Location.Server).Split('.')[0]

    $activeTenantDatabase = Get-AzureRmSqlDatabase `
                                -ResourceGroupName $Catalog.Database.ResourceGroupName `
                                -ServerName $tenantServerName `
                                -DatabaseName $tenantDatabaseName `
                                -ErrorAction SilentlyContinue

    # Delete active tenant database
    if ($activeTenantDatabase)
    {
        $deletedTenantDatabase = Remove-AzureRmSqlDatabase `
                                    -ResourceGroupName $Catalog.Database.ResourceGroupName `
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

        [parameter(Mandatory=$false)]
        [object]$SourceDatabase = $null
    )

    $config = Get-Configuration

    $tenantServerName = $SourceDatabase.Name.Split('/',2)[0]
    $sourceDatabaseName = $SourceDatabase.Name.Split('/',2)[1]
    $commandText = "ALTER DATABASE [$sourceDatabaseName] MODIFY Name = [$TargetDatabaseName];"

    Invoke-SqlAzureWithRetry `
        -Username $config.TenantAdminUserName `
        -Password $config.TenantAdminPassword `
        -ServerInstance ($tenantServerName + ".database.windows.net") `
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
                                        -DatabaseName $TargetDatabaseName                                      

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
    $tenantServerName = ($tenantMapping.Shard.Location.Server).Split('.')[0]

    # Choose active tenant database as database to rename if no database specified 
    if (!$TenantDatabaseObject)
    {
        $TenantDatabaseObject = Get-AzureRmSqlDatabase `
                                -ResourceGroupName $Catalog.Database.ResourceGroupName `
                                -ServerName $tenantServerName `
                                -DatabaseName $tenantDatabaseName
    }

    # Rename active tenant database using T-SQL on the 'master' database
    Write-Output "Renaming SQL database '$($TenantDatabaseObject.DatabaseName)' to '$TargetDatabaseName'..."

    $renamedDatabaseObject = Rename-Database -SourceDatabase $TenantDatabaseObject -TargetDatabaseName $TargetDatabaseName
       
    return $renamedDatabaseObject
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
        [object]$Database    
    )
   
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
                State = 'updated',
                LastUpdated = source.LastUpdated
        WHEN NOT MATCHED THEN
            INSERT (ServerName, DatabaseName, ServiceObjective, ElasticPoolName, State, LastUpdated)
            VALUES (ServerName, DatabaseName, ServiceObjective, ElasticPoolName,'created',LastUpdated);"
    
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

    [parameter(Mandatory=$true)]
    [int]$BufferDatabases

    )

    $provisionConfig = Get-ProvisionConfiguration

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
             $($BufferDatabases),
             CURRENT_TIMESTAMP))
        AS [source]
            (ServerName, ElasticPoolName, Edition, Dtu, DatabaseDtuMax, DatabaseDtuMin, StorageMB, BufferDatabases, LastUpdated)
        ON target.ServerName = source.ServerName AND target.ElasticPoolName = source.ElasticPoolName 
        WHEN MATCHED THEN
            UPDATE SET
                Edition = source.Edition,
                Dtu = source.Dtu,
                DatabaseDtuMax = source.DatabaseDtuMax,
                DatabaseDtuMin = source.DatabaseDtuMin,
                StorageMB = source.StorageMB,
                BufferDatabases = source.BufferDatabases,            
                State = 'updated',
                LastUpdated = source.LastUpdated
        WHEN NOT MATCHED THEN
            INSERT (ServerName, ElasticPoolName, DatabasesMax, Edition, Dtu, DatabaseDtuMax, DatabaseDtuMin, StorageMB, BufferDatabases, ProvisioningState, State, LastUpdated)
            VALUES (ServerName, ElasticPoolName, $($provisionConfig.ElasticPoolDatabasesMax), Edition, Dtu, DatabaseDtuMax, DatabaseDtuMin, StorageMB, BufferDatabases,'normal','created', LastUpdated);"
    
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
        [object]$Server
    )

    $provisionConfig = Get-ProvisionConfiguration
   
    $commandText = "
        MERGE INTO [dbo].[Servers] AS [target]
        USING (VALUES
            ('$($Server.ServerName)', '$($Server.Location.Replace(' ','').ToLower())', CURRENT_TIMESTAMP))
        AS [source]
            (ServerName, Location, LastUpdated)
        ON target.ServerName = source.ServerName 
        WHEN NOT MATCHED THEN
            INSERT (ServerName, ElasticPoolsMax, ProvisioningState, State, Location, LastUpdated)
            VALUES (ServerName, $($provisionConfig.ServerElasticPoolsMax),'normal', 'created', Location, LastUpdated);"
    
    Invoke-SqlAzureWithRetry `
        -ServerInstance $Catalog.FullyQualifiedServerName `
        -Database $Catalog.Database.DatabaseName `
        -Query $commandText `
        -UserName $config.CatalogAdminUserName `
        -Password $config.CatalogAdminPassword
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

    $tenantMapping = ($Catalog.ShardMap).GetMappingForKey($TenantKey)

    # Mark tenant offline if its mapping status is online, and suppress output
    if ($tenantMapping.Status -eq "Online")
    {
        ($Catalog.ShardMap).MarkMappingOffline($tenantMapping) >$null
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
                $True
            } 
            Else 
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
                return $True
            } 
            Else 
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
                return $True
            } 
            Else 
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
    Validates a venue type name contains only legal characters
#>
function Test-ValidVenueType
{
    param(
        [parameter(Mandatory=$true)]
        [ValidateScript(
        {
            if ($_ -match '^[A-Za-z][A-Za-z]*$') 
            {
                return $True
            } 
            Else 
            {
                throw "'$_' is invalid.  Venue type names can only include a-z, A-Z."
            }
         }
         )]
        [string]$VenueType,

        [parameter(Mandatory=$true)]
        [object]$Catalog
    )
    $config = Get-Configuration

    #$language = (Get-Culture).Name
    $language = "en-us"

    $commandText = "
        SELECT Count(VenueType) AS Count FROM [dbo].[VenueTypes]
        WHERE VenueType = '$VenueType'"

    $results = Invoke-SqlAzureWithRetry `
                    -ServerInstance $Catalog.FullyQualifiedServerName `
                    -Username $config.TenantAdminuserName `
                    -Password $config.TenantAdminPassword `
                    -Database $Catalog.Database.DatabaseName `
                    -Query $commandText

    if($results.Count -ne 1)
    {
        throw "Error: '$VenueType' is not a recognized venue type."
    }
}