<#
.SYNOPSIS
  Submits a request to provision a new Wingtip Tickets Platform (WTP) tenant   

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

Param(
    [Parameter(Mandatory=$true)]
    [string]$WtpResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$WtpUser,

    [Parameter(Mandatory=$true)]
    [string]$TenantName,

    [Parameter(Mandatory=$false)]
    [string]$VenueType = "MultiPurposeVenue",

    [Parameter(Mandatory=$false)]
    [ValidateSet('free','standard','premium')]
    [string]$ServicePlan = "standard",

    [Parameter(Mandatory=$true)]
    [string]$Location
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
Test-LegalVenueTypeName -Catalog $catalog -VenueType $VenueType > $null

# Compute the tenant key from the tenant name, key to be used to register the tenant in the catalog 
$tenantKey = Get-TenantKey -TenantName $TenantName 

# Check if a tenant with this key is aleady registered in the catalog
if (Test-TenantKeyInCatalog -Catalog $catalog -TenantKey $tenantKey)
{
    throw "A tenant with name '$TenantName' is already registered in the catalog."    
}

$commandText = "
    SELECT Count(TenantName) AS Count FROM TenantRequests
    WHERE TenantName = '$TenantName' AND RequestState = 'submitted'"

$results = Invoke-SqlAzureWithRetry `
            -ServerInstance $Catalog.FullyQualifiedServerName `
            -Username $config.TenantAdminuserName `
            -Password $config.TenantAdminPassword `
            -Database $Catalog.Database.DatabaseName `
            -Query $commandText `
            -ConnectionTimeout 30 `
            -QueryTimeout 30

if($results.Count -gt 0)
{
    throw "New tenant request already exists for '$TenantName'."
}

$commandText = "
    INSERT INTO TenantRequests
        (TenantName, ServicePlan, VenueType, Location, Requested, RequestState, LastUpdated)
    VALUES 
        ('$TenantName','$ServicePlan','$VenueType','$Location', CURRENT_TIMESTAMP, 'submitted', CURRENT_TIMESTAMP);"

Invoke-SqlAzureWithRetry `
    -ServerInstance $Catalog.FullyQualifiedServerName `
    -Username $config.TenantAdminuserName `
    -Password $config.TenantAdminPassword `
    -Database $Catalog.Database.DatabaseName `
    -Query $commandText `
    -ConnectionTimeout 30 `
    -QueryTimeout 30 

Write-Output "New tenant request submitted for '$TenantName'"