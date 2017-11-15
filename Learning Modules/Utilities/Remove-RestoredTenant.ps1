<#
.SYNOPSIS
  Removes a previously restored tenant entry with _old suffix.
#>
[cmdletbinding()]
param (
    [parameter(Mandatory=$true)]
    [string]$WtpResourceGroupName,

    [parameter(Mandatory=$true)]
    [string]$WtpUser,

    [parameter(Mandatory=$true)]
    [string]$TenantName,

    # NoEcho stops the output of the signed in user to prevent double echo  
    [parameter(Mandatory=$false)]
    [switch] $NoEcho
)


# Stop execution on error 
#$ErrorActionPreference = "Stop"

Import-Module $PSScriptRoot\..\Common\CatalogAndDatabaseManagement -Force
Import-Module $PSScriptRoot\..\Common\SubscriptionManagement -Force

# Get Azure credentials if not already logged on
Initialize-Subscription -NoEcho:$NoEcho.IsPresent

$catalog = Get-Catalog `
            -ResourceGroupName $WtpResourceGroupName `
            -WtpUser $WtpUser `

$restoredTenantName = (Get-NormalizedTenantName -TenantName $TenantName) + "_old"

$tenantKey = Get-TenantKey -TenantName $restoredTenantName

if(Test-TenantKeyInCatalog -Catalog $catalog -TenantKey $tenantKey)
{
    Remove-Tenant `
        -Catalog $catalog `
        -TenantKey $tenantKey

    Write-Output "'$restoredTenantName' is removed."
}
else
{
    Write-Output "'$restoredTenantName' is not in the catalog."
    exit
}
