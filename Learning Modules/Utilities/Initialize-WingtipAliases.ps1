<#
.SYNOPSIS
    Creates DNS aliases for the catalog database and tenant databases. Using DNS aliases allows for a seamless recovery and repatriation of the WingtipSaaS app without updating the app.
    After creating DNS aliases for tenants, tenant server entries in the catalog are updated to the alias location.
#>
[cmdletbinding()]
param(
    # NoEcho stops the output of the signed in user to prevent double echo  
    [parameter(Mandatory=$false)]
    [switch] $NoEcho
)

Import-Module $PSScriptRoot\..\Common\SubscriptionManagement -Force
Import-Module $PSScriptRoot\..\Common\CatalogAndDatabaseManagement -Force
Import-Module $PSScriptRoot\..\WtpConfig -Force
Import-Module $PSScriptRoot\..\UserConfig -Force

# Get Azure credentials if not already logged on
Initialize-Subscription -NoEcho:$NoEcho.IsPresent

# Get deployment configuration  
$wtpUser = Get-UserConfig
$config = Get-Configuration

# Get catalog
Write-Output "Getting catalog..."
$catalogServerName = $config.CatalogServerNameStem + $wtpUser.Name + $config.OriginRoleSuffix
$catalogAliasName = "catalog-" + $wtpUser.Name
$fullyQualifiedCatalogDnsAlias = $catalogAliasName + ".database.windows.net"


# Get catalog alias if it exists or create one if it doesn't exist
try 
{
    Resolve-DnsName $fullyQualifiedCatalogDnsAlias -ErrorAction Stop > $null
    Write-Output "Catalog alias already exists."
}
catch
{   
    Write-Output "Creating alias for catalog database..."

    # Create DNS alias for catalog database
    Set-DnsAlias `
        -ResourceGroupName $wtpUser.ResourceGroupName `
        -ServerName $catalogServerName `
        -ServerDNSAlias $catalogAliasName `
        -PollDnsUpdate
}

# Initialize catalog tables 
& "$PSScriptRoot\Initialize-CatalogSyncTables.ps1" -WtpResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name -NoEcho

# Get the databases of all tenants currently registered in the catalog
$catalogObject = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name
$tenantDatabaseList = (Get-TenantDatabaseLocations -Catalog $catalogObject).Location
$tenantAliasConfig = @()

# Get tenant alias if it exists or create one if it doesn't exist 
foreach ($tenantDatabase in $tenantDatabaseList)
{
    $tenantName = (Get-TenantNameFromTenantDatabase -TenantServerFullyQualifiedName $tenantDatabase.Server -TenantDatabaseName $tenantDatabase.Database).VenueName
    $fullyQualifiedTenantServerName = $tenantDatabase.Server 
    $tenantServerName = $fullyQualifiedTenantServerName.split('.',2)[0]
    $tenantAliasName = $tenantDatabase.Database + "-" + $wtpUser.Name
    $fullyQualifiedTenantDnsAlias = $tenantAliasName + ".database.windows.net"

    try 
    {
        Resolve-DnsName $fullyQualifiedTenantDnsAlias -ErrorAction Stop >$null
        Write-Output "Alias for tenant '$tenantName' already exists"
    }
    catch
    {
        Write-Output "Creating alias for tenant '$tenantName'..."

        # Create DNS alias for tenant 
        Set-DnsAlias `
            -ResourceGroupName $wtpUser.ResourceGroupName `
            -ServerName $tenantServerName `
            -ServerDNSAlias $tenantAliasName           
    }
    finally
    {
        $tenantAliasConfig += New-Object PSObject -Property @{TenantName = $tenantName; TenantAlias = $tenantAliasName}          
    }
}

# Poll DNS for tenant alias status 
$tenantAliasInProgress = $true
Write-Output "---`nChecking DNS records for tenant aliases..."
while ($tenantAliasInProgress)
{
    foreach ($tenant in $tenantAliasConfig)
    {
        try
        {
            Write-Output "Checking DNS record for tenant '$($tenant.TenantName)' alias..."

            # Check if DNS alias exists
            $fullyQualifiedTenantDnsAlias = $tenant.TenantAlias + ".database.windows.net"
            $tenantServerName = Get-ServerNameFromAlias -fullyQualifiedTenantAlias $fullyQualifiedTenantDnsAlias -ErrorAction Stop
            $tenantAliasInProgress = $false

            # Update catalog to include tenant alias
            $tenantKey = Get-TenantKey -TenantName $tenant.TenantName
            $tenantShard = ($catalogObject.ShardMap.GetMappingForKey($tenantKey)).Shard.Location
            if ($tenantShard.Server -Match "home.database.windows.net$")
            {
                Write-Output "Updating catalog entry for tenant '$($tenant.TenantName)'..."
             
                Update-TenantEntryInCatalog `
                    -Catalog $catalogObject `
                    -TenantName $tenant.TenantName `
                    -RequestedTenantServerName $tenant.TenantAlias
            }
            else
            {
                Write-Output "`tCatalog entry for tenant '$($tenant.TenantName)' already updated"    
            }
        }
        catch
        {
            # Tenant DNS alias does not exist. Retry again in a few seconds 
            $tenantAliasInProgress = $true
            break
        }
    }

    if ($tenantAliasInProgress)
    {
        Write-Output "---`nDNS record does not yet exist. Checking again in 5 seconds..."
            
        # Poll again in 5 seconds
        Start-Sleep 5
    }

}

Write-Output "Tenant and catalog alias created and online."



