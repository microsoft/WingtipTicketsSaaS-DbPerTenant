<#
.SYNOPSIS
    Deploys a SQLcommand against all tenant databases in the catalog sequentially.  Assumes command is idempotent as   
    it will do a simply one-time retry.  For serious work use Elastic Jobs. 
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
    try
    {
        Write-Output "Applying command to database '$($shard.Location.Database)' on server '$($shard.Location.Server)'."
        Invoke-Sqlcmd `
            -Username $adminUserName `
            -Password $adminPassword `
            -ServerInstance $shard.Location.Server `
            -Database $shard.Location.Database `
            -ConnectionTimeout 30 `
            -QueryTimeout $QueryTimeout `
            -Query $CommandText `
            -EncryptConnection
    }
    catch
    {
        # one time retry if errors
        Invoke-Sqlcmd `
            -Username $adminUserName `
            -Password $adminPassword `
            -ServerInstance $shard.Location.Server `
            -Database $shard.Location.Database `
            -ConnectionTimeout 30 `
            -QueryTimeout $QueryTimeout `
            -Query $CommandText `
            -EncryptConnection        
    }

}