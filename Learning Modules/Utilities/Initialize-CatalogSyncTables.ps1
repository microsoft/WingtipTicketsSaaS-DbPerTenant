<#
.SYNOPSIS
    Initializes extended tables in the catalog database that will store tenant configuration info.
    The script is idempotent as it will retry on error, dropped connection etc.  
#>
[cmdletbinding()]
param(
[Parameter(Mandatory=$true)]
[string]$WtpResourceGroupName,
    
[Parameter(Mandatory=$true)]
[string]$WtpUser,

[Parameter(Mandatory=$false)]
[int]$QueryTimeout = 60,

# NoEcho stops the output of the signed in user to prevent double echo  
[parameter(Mandatory=$false)]
[switch] $NoEcho
)
$WtpUser = $WtpUser.ToLower()

Import-Module $PSScriptRoot\..\Common\SubscriptionManagement -Force
Import-Module $PSScriptRoot\..\Common\CatalogAndDatabaseManagement -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription -NoEcho:$NoEcho.IsPresent

# Get configuration variables 
$config = Get-Configuration

# Get the tenant catalog
$catalog = Get-Catalog -ResourceGroupName $WtpResourceGroupName -WtpUser $WtpUser

# Initialize extended catalog tables 
$adminUserName = $config.CatalogAdminUserName
$adminPassword = $config.CatalogAdminPassword 
$catalogDatabase = $catalog.Database.DatabaseName
$catalogServer = $catalog.Database.ServerName
$fullyQualifiedCatalogServerName = $catalogServer + ".database.windows.net"
$commandText = "
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Servers')
        CREATE TABLE [dbo].[Servers]
        (
            [ServerName] NVARCHAR(128) NOT NULL PRIMARY KEY, 
            [Location] NVARCHAR (30) NOT NULL,
            [State] NVARCHAR(30) NOT NULL DEFAULT 'initial',
            [RecoveryState] NVARCHAR(30) NULL,
            [LastUpdated] DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        )  
    GO

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ElasticPools')
        CREATE TABLE [dbo].[ElasticPools]
        ( 
            [ServerName] NVARCHAR(128) NOT NULL,
            [ElasticPoolName] NVARCHAR(128) NOT NULL, 
            [Dtu] INT NOT NULL, 
            [Edition] VARCHAR(20) NOT NULL, 
            [DatabaseDtuMax] INT NOT NULL, 
            [DatabaseDtuMin] INT NOT NULL,
            [StorageMB] INT NOT NULL, 
            [State] NVARCHAR(30) NOT NULL DEFAULT 'initial',
            [RecoveryState] NVARCHAR(30) NULL,
            [LastUpdated] DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, 
            CONSTRAINT [PK_ElasticPools] PRIMARY KEY ([ServerName], [ElasticPoolName])   
        )
    GO

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Databases')
        CREATE TABLE [dbo].[Databases]
        (
            [ServerName] NVARCHAR(128) NOT NULL,   
            [DatabaseName] NVARCHAR(128) NOT NULL,
            [ServiceObjective] NVARCHAR(50) NOT NULL, 
            [ElasticPoolName] NVARCHAR(128) NULL, 
            [State] NVARCHAR(30) NOT NULL DEFAULT 'initial',
            [RecoveryState] NVARCHAR(30) NULL,
            [LastUpdated] DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            CONSTRAINT [PK_Databases] PRIMARY KEY CLUSTERED ([ServerName],[DatabaseName])
        )
    GO

    IF COL_LENGTH('dbo.Tenants', 'RecoveryState') IS NULL
        ALTER TABLE [dbo].[Tenants] ADD RecoveryState NVARCHAR(30) NOT NULL DEFAULT 'n/a'
    GO 

    IF COL_LENGTH('dbo.Tenants', 'LastUpdated') IS NULL
        ALTER TABLE [dbo].[Tenants] ADD LastUpdated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    GO   

    CREATE OR ALTER VIEW [dbo].[TenantsExtended]
    AS        
        WITH databasesWithPriority AS (
            SELECT *, RANK() OVER (PARTITION BY DatabaseName ORDER BY LastUpdated DESC) AS databasePriority FROM Databases  
        )
        SELECT      tenant.TenantId,
                    tenant.TenantName,
                    CASE
                        WHEN mapping.Status = 1 THEN 'Online'
                        WHEN mapping.Status = 0 THEN 'Offline'
                    ELSE 'Unknown'
                    END AS TenantStatus,
                    tenant.ServicePlan,
                    CASE
                        WHEN ((shard.ServerName NOT LIKE '%home.database.windows.net') AND (shard.ServerName NOT LIKE '%recovery.database.windows.net')) THEN shard.ServerName
                        ELSE NULL
                    END AS TenantAlias,
                    CASE
                        WHEN ((shard.ServerName LIKE '%home.database.windows.net') OR (shard.ServerName LIKE '%recovery.database.windows.net')) THEN shard.ServerName
                        ELSE tenantDB.ServerName
                    END AS ServerName,
                    shard.DatabaseName,
                    tenant.RecoveryState AS TenantRecoveryState,
                    tenantServer.Location,
                    CASE
                        WHEN tenantDB.LastUpdated IS NULL THEN tenant.LastUpdated
                        WHEN (tenantDB.LastUpdated > tenant.LastUpdated) THEN tenantDB.LastUpdated
                        WHEN (tenantDB.LastUpdated < tenant.LastUpdated) THEN tenant.LastUpdated
                        ELSE tenant.LastUpdated
                    END AS LastUpdated
        FROM        [dbo].[Tenants] AS tenant
        JOIN        [__ShardManagement].[ShardMappingsGlobal] AS mapping ON (tenant.TenantId = mapping.MinValue)
        JOIN        [__ShardManagement].[ShardMapsGlobal] AS map ON (map.ShardMapId = mapping.ShardMapId)
        JOIN        [__ShardManagement].[ShardsGlobal] as shard ON (shard.ShardId = mapping.ShardId AND shard.ShardMapId = map.ShardMapId AND mapping.ShardMapId = map.ShardMapId)
        LEFT JOIN   databasesWithPriority AS tenantDB ON (tenantDB.DatabaseName = shard.DatabaseName AND tenantDB.databasePriority = 1)
        LEFT JOIN   Servers AS tenantServer ON (tenantServer.ServerName = tenantDB.ServerName)
        WHERE       (map.Name = 'tenantcatalog');
    GO  
"
Write-Output "Initializing extended tables in the catalog database..."
Invoke-SqlcmdWithRetry `
    -Username $adminUserName `
    -Password $adminPassword `
    -ServerInstance $fullyQualifiedCatalogServerName `
    -Database $catalogDatabase `
    -ConnectionTimeout 30 `
    -QueryTimeout $QueryTimeout `
    -Query $commandText 