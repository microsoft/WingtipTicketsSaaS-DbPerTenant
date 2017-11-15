<#
.SYNOPSIS
    Deploys a SQL script against all tenant databases in the catalog sequentially and to the golden tenant database.
    The script should be idempotent as it will retry on error, dropped connection etc.  
    Lightweight solution to fanout deployment.  Use Elastic Jobs for a more robust solution. 
#>
[cmdletbinding()]
param(
[Parameter(Mandatory=$true)]
[string]$WtpResourceGroupName,
    
[Parameter(Mandatory=$true)]
[string]$WtpUser,

[Parameter(Mandatory=$true)]
[string]$CommandText,

[int]$QueryTimeout = 60
)
$WtpUser = $WtpUser.ToLower()

Import-Module $PSScriptRoot\..\Common\SubscriptionManagement -Force
Import-Module $PSScriptRoot\..\Common\CatalogAndDatabaseManagement -Force

$config = Get-Configuration

## Apply script to deployed tenant databases

$adminUserName = $config.TenantAdminUserName
$adminPassword = $config.TenantAdminPassword

# Get the catalog for the current user
$catalog = Get-Catalog `
    -ResourceGroupName $WtpResourceGroupName `
    -WtpUser $WtpUser
    
# Get all the databases in the catalog shard map
$shards = Get-Shards -ShardMap $catalog.ShardMap

foreach ($shard in $Shards)
{

    Write-Output "Applying script to database '$($shard.Location.Database)' on server '$($shard.Location.Server)'."
    Invoke-SqlcmdWithRetry `
        -Username $adminUserName `
        -Password $adminPassword `
        -ServerInstance $shard.Location.Server `
        -Database $shard.Location.Database `
        -ConnectionTimeout 30 `
        -QueryTimeout $QueryTimeout `
        -Query $CommandText

}

## Apply script to the golden tenant database on the catalog server so new tenants databases will have the script applied

$adminUserName = $config.CatalogAdminUserName
$adminPassword = $config.CatalogAdminPassword

$catalogServer = $config.CatalogServerNameStem + $WtpUser
$fullyQualifiedCatalogServerName = $catalogServer + ".database.windows.net"
$goldenTenantDatabase = $config.GoldenTenantDatabaseName

    Write-Output "Applying script to database '$goldenTenantDatabase' on server '$catalogServer'."
    Invoke-SqlcmdWithRetry `
        -Username $adminUserName `
        -Password $adminPassword `
        -ServerInstance $fullyQualifiedCatalogServerName `
        -Database $goldenTenantDatabase `
        -ConnectionTimeout 30 `
        -QueryTimeout $QueryTimeout `
        -Query $CommandText 