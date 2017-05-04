<#
.SYNOPSIS
  Find the first event with no tickets and delete it from venue registered on Wingtip platform
#>
[cmdletbinding()]
param (
    [parameter(Mandatory=$true)]
    [string]$WtpResourceGroupName,

    [parameter(Mandatory=$true)]
    [string]$WtpUser,

    [parameter(Mandatory=$true)]
    [string]$TenantName
)

Import-Module $PSScriptRoot\..\Common\CatalogAndDatabaseManagement -Force
Import-Module $PSScriptRoot\..\Common\SubscriptionManagement -Force

# Get Azure credentials if not already logged on
Initialize-Subscription

# Get catalog database that contains metadata about all Wingtip tenant databases
$catalog = Get-Catalog `
            -ResourceGroupName $WtpResourceGroupName `
            -WtpUser $WtpUser `

$normalizedTenantName = Get-NormalizedTenantName -TenantName $TenantName

$tenantKey = Get-TenantKey -TenantName $normalizedTenantName

# Exit script if tenant is not in the catalog 
if(!(Test-TenantKeyInCatalog -Catalog $catalog -TenantKey $tenantKey))
{
    Write-Output "'$TenantName' is not in the catalog."
    exit
}

# Get catalog username and password configuration 
$config = Get-Configuration

$tenantMapping = ($catalog.ShardMap).GetMappingForKey($tenantKey)

# Get tenant database and server names 
$tenantDatabaseName = $tenantMapping.Shard.Location.Database
$fullyQualifiedTenantServerName = $tenantMapping.Shard.Location.Server

# Get the first unsold event on the tenant database 
$queryText = "SELECT TOP(1) EventName FROM EventsWithNoTickets"
$eventName = Invoke-Sqlcmd `
                -ServerInstance $fullyQualifiedTenantServerName `
                -Username $config.TenantAdminuserName `
                -Password $config.TenantAdminPassword `
                -Database $tenantDatabaseName `
                -Query $queryText `
                -ConnectionTimeout 30 `
                -QueryTimeout 30 `
                -EncryptConnection

if ($eventName)
{
    # Delete the first unsold event on the tenant database 
    $queryText = "
            DECLARE @TargetEventID int
            SET @TargetEventID = (SELECT TOP(1) EventId FROM EventsWithNoTickets)
            EXEC sp_DeleteEvent @TargetEventID
            "
    Invoke-Sqlcmd `
        -ServerInstance $fullyQualifiedTenantServerName `
        -Username $config.TenantAdminuserName `
        -Password $config.TenantAdminPassword `
        -Database $tenantDatabaseName `
        -Query $queryText `
        -ConnectionTimeout 30 `
        -QueryTimeout 30 `
        -EncryptConnection

    Write-Verbose "Deleted event '$($eventName.EventName)' from $TenantName venue."
    return $eventName.EventName
}
else 
{
    Write-Error "There are no unsold events to delete for tenant $TenantName. Run the ticket generator script to generate more events."
    exit 
}


