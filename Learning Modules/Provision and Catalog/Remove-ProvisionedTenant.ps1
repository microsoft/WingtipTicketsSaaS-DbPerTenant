<#
.SYNOPSIS
  Deletes a tenant.  Deletes the database and all entries from the catalog. 
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


# Stop execution on error 
#$ErrorActionPreference = "Stop"

Import-Module $PSScriptRoot\..\Common\CatalogAndDatabaseManagement -Force
Import-Module $PSScriptRoot\..\Common\SubscriptionManagement -Force

# Get Azure credentials if not already logged on
Initialize-Subscription

$catalog = Get-Catalog `
            -ResourceGroupName $WtpResourceGroupName `
            -WtpUser $WtpUser `

$provisionedTenantName = (Get-NormalizedTenantName -TenantName $TenantName)

$tenantKey = Get-TenantKey -TenantName $provisionedTenantName

# Check if the tenant exists. If so, remove the tenant
if(Test-TenantKeyInCatalog -Catalog $catalog -TenantKey $tenantKey)
{
    Remove-Tenant `
        -Catalog $catalog `
        -TenantKey $tenantKey

    Write-Output "'$TenantName' is removed."
}
else
{
    Write-Output "'$TenantName' is not in the catalog."
    exit
}
