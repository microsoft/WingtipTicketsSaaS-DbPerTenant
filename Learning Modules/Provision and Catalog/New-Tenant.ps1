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
function New-TenantX 
{
    Param(
        [Parameter(Mandatory=$true)]
        [string]$WtpResourceGroupName,
    
        [Parameter(Mandatory=$true)]
        [string]$WtpUser,

        [Parameter(Mandatory=$true)]
        [string]$TenantName,

        [Parameter(Mandatory=$false)]
        [string]$VenueType
    )

    $WtpUser = $WtpUser.ToLower()

    Import-Module $PSScriptRoot\..\Common\SubscriptionManagement -Force
    Import-Module $PSScriptRoot\..\Common\CatalogAndDatabaseManagement -Force

    $config = Get-Configuration

    # Ensure logged in to Azure
    Initialize-Subscription

    ## MAIN SCRIPT ## ----------------------------------------------------------------------------

    # Get the catalog 
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

    $tenantServerName = $config.TenantServerNameStem + $WtpUser
    $tenantPoolName = $config.TenantPoolNameStem + "1"

    # Deploy and initialize a database for this tenant 
    $tenantDatabase = New-TenantDatabase `
        -ResourceGroupName $WtpResourceGroupName `
        -ServerName $tenantServerName `
        -ElasticPoolName $tenantPoolName `
        -TenantName $TenantName `
        -VenueType $VenueType `
        -WtpUser $WtpUser

    # Register the tenant and database in the catalog
    Add-TenantDatabaseToCatalog -Catalog $catalog `
        -TenantName $TenantName `
        -TenantKey $tenantKey `
        -TenantDatabase $tenantDatabase `

    Write-Output "Provisioning complete for tenant '$TenantName'"
}