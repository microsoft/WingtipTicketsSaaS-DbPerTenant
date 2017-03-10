Import-Module $PSScriptRoot\..\Common\CatalogAndDatabaseManagement -Force

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
    
    $catalogServerName = "catalog-" + $WtpUser
    $catalogServerFullyQualifiedName = $catalogServerName + ".database.windows.net"
    $adminUserName = "developer"
    $adminPassword = "P@ssword1"

    $catalogDatabaseName = "customercatalog"
    $shardMapName = "customercatalog"
    
    # Check catalog database exists
    $catalogDatabase = Get-AzureRmSqlDatabase `
        -ResourceGroupName $ResourceGroupName `
        -ServerName $catalogServerName `
        -DatabaseName $catalogDatabaseName `
        -ErrorAction Stop

    # Initialize shard map manager from catalog database
    [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManager]$shardMapManager = Get-ShardMapManager `
        -SqlServerName $catalogServerFullyQualifiedName `
        -UserName $adminUserName `
        -Password $adminPassword `
        -SqlDatabaseName $catalogDatabaseName `

    if (!$shardmapManager)
    {
        throw "Failed to initialize shard map manager from '$catalogDatabaseName' database. Ensure the catalog has been initialized and try again."
    }

    # Initialize shard map
    [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMap]$shardMap = Get-ListShardMap `
        -KeyType $([int]) `
        -ShardMapManager $shardMapManager `
        -ListShardMapName $shardMapName
 
    If (!$shardMap)
    {
        throw "Failed to load shard map '$shardMapName' from '$catalogDatabaseName' database"       
    }
    else
    {
        $catalog = New-Object PSObject -Property @{
            ShardMapManager=$shardMapManager
            ShardMap=$shardMap
            ServerName = $catalogServerName
            FullyQualifiedServerName = $catalogServerFullyQualifiedName
            DatabaseName = $catalogDatabaseName
            } 

        return $catalog
    }
} 


<#
.SYNOPSIS
    Tests if a tenant key is registered. Returns true if the key exists in the catalog or false if it does not.
#>
function Test-TenantKeyInCatalog
{
    Param(
        [parameter(Mandatory=$true)]
        [object]$Catalog,
        
        [parameter(Mandatory=$true)]
        [int32] $TenantKey    
    )

    try
    {
        ($Catalog.ShardMap).TryGetMappingForKey($tenantKey) > $null    
        return $true
    }
    catch
    {
        return $false
    }
}

<#
.SYNOPSIS
    Creates a tenant database and imports the tenant initialization bacpac using an ARM template, then
    updates the Venue information and with the default VenueType.  Requires tenantdatabasetemplate.json.
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
        [string]$VenueType = "MultiPurposeVenue",

        [parameter(Mandatory=$false)]
        [string]$PostalCode = '98052',

        [parameter(Mandatory=$false)]
        [string]$CountryCode = 'USA'                
    )

    # Check the server exists
    $Server = Get-AzureRmSqlServer -ResourceGroupName $ResourceGroupName -ServerName $ServerName 

    if (!$Server)
    {
        throw "Could not find tenant server '$ServerName'."
    }

    $normalizedTenantName = $TenantName.Replace(' ', '').ToLower()
    
    # Check the tenant database does not exist

    $database = Get-AzureRmSqlDatabase -ResourceGroupName $ResourceGroupName `
        -ServerName $ServerName `
        -DatabaseName $normalizedTenantName `
        -ErrorAction SilentlyContinue
        
    if ($database)
    {
        throw "Tenant database '$($database.DatabaseName)' already exists.  Exiting..."
    }

    # Use an ARM template to deploy the tenant database and import the initialization bacpac
    $deployment = New-AzureRmResourceGroupDeployment `
        -TemplateFile "$PSScriptRoot\TenantDatabaseTemplate.json" `
        -Location $($Server.Location) `
        -ResourceGroupName $ResourceGroupName `
        -ServerName $ServerName `
        -AdminUserName "developer" `
        -AdminUserPassword "P@ssword1" `
        -DatabaseName $normalizedTenantName `
        -ElasticPoolName $ElasticPoolName `
        -BacpacUrl "https://wtpdeploystorageaccount.blob.core.windows.net/wingtip-bacpacsvold/wingtiptenantdb.bacpac" `
        -StorageKeyType "SharedAccessKey" `
        -StorageKey (ConvertTo-SecureString -String "?" -AsPlainText -Force) `
        -ErrorAction Stop `
        -Verbose

    # Initialize tenant info in the tenant database (idempotent) 
    
    $adminUserName = 'developer'
    $adminPassword = 'P@ssword1'
    $emaildomain = $normalizedTenantName
    if ($emailDomain.Length -gt 20) {$emailDomain = $emailDomain.Substring(0,20)}
    $VenueAdminEmail = "admin@" + $emailDomain + ".com"
    
    $commandText = "
        DELETE FROM Venues
        INSERT INTO Venues 
            (VenueName, VenueType, AdminEmail, PostalCode, CountryCode  )
        VALUES 
            ('$TenantName', '$VenueType','$VenueAdminEmail', '$PostalCode', '$CountryCode');"

    Invoke-Sqlcmd `
        -ServerInstance $($ServerName + ".database.windows.net") `
        -Username $adminUserName `
        -Password $adminPassword `
        -Database $normalizedTenantName `
        -Query $commandText `
        -ConnectionTimeout 30 `
        -QueryTimeout 30 `
        -EncryptConnection          
            
    # Return the created database
    Get-AzureRmSqlDatabase -ResourceGroupName $ResourceGroupName `
        -ServerName $ServerName `
        -DatabaseName $normalizedTenantName
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
    Add-Shard -ShardMap $($Catalog.ShardMap) `
        -SqlServerName $tenantServerFullyQualifiedName `
        -SqlDatabaseName $($TenantDatabase.DatabaseName) `
        -Verbose

    # Add the tenant-to-database mapping to the catalog (idempotent)
    Add-ListMapping `
        -KeyType $([int]) `
        -ListShardMap $($Catalog.ShardMap) `
        -SqlServerName $tenantServerFullyQualifiedName `
        -SqlDatabaseName $($TenantDatabase.DatabaseName) `
        -ListPoint $TenantKey

    # Add the tenant name to the catalog as extended meta data (idempotent)
    Add-ExtendedTenantMetaDataToCatalog `
        -Catalog $Catalog `
        -TenantKey $TenantKey `
        -TenantName $TenantName
}

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
        [int]$TenantKey,

        [parameter(Mandatory=$true)]
        [string]$TenantName    
    )

    $adminUserName = "developer"
    $adminPassword = "P@ssword1"

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

    Invoke-Sqlcmd `
        -ServerInstance $($Catalog.FullyQualifiedServerName) `
        -Username $adminUserName `
        -Password $adminPassword `
        -Database $($Catalog.DatabaseName) `
        -Query $commandText `
        -ConnectionTimeout 30 `
        -QueryTimeout 30 `
        -EncryptConnection
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
     
    $adminUserName = 'developer'
    $adminPassword = 'P@ssword1'

    $commandText = "Select Top 1 VenueName from Venues"

    Invoke-Sqlcmd `
        -ServerInstance $TenantServerFullyQualifiedName `
        -Username $adminUserName `
        -Password $adminPassword `
        -Database $TenantDatabaseName `
        -Query $commandText `
        -ConnectionTimeout 30 `
        -QueryTimeout 30 `
        -EncryptConnection
}