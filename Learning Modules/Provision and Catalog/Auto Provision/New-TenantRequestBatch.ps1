<#
.SYNOPSIS
  Creates and submits a batch of requests to provision a Wingtip Tickets Platform (WTP) tenants   

.DESCRIPTION
Creates and submits a batch of requests to provision a Wingtip Tickets Platform (WTP) tenants

.PARAMETER WtpResourceGroupName
  The resource group name used during the deployment of the WTP app (case sensitive)

.PARAMETER WtpUser
  The 'User' value that was entered during the deployment of the WTP app

.PARAMETER NewTenants
  An array of Tenant Names plus Venue Types
#>

Param(
    [Parameter(Mandatory=$true)]
    [string]$WtpResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$WtpUser,

    [Parameter(Mandatory=$true)]
    [string]$Location,

    [Parameter(Mandatory=$true)]
    [string[][]]$NewTenants


)
$start = Get-Date
$WtpUser = $WtpUser.ToLower()
$location = $Location.Replace(" ","").ToLower()

Import-Module $PSScriptRoot\..\..\Common\SubscriptionManagement -Force
Import-Module $PSScriptRoot\..\..\Common\CatalogAndDatabaseManagement -Force

$config = Get-Configuration

## MAIN SCRIPT ## ----------------------------------------------------------------------------

# Ensure logged in to Azure
Initialize-Subscription

# Get the catalog 
$catalog = Get-Catalog -ResourceGroupName $WtpResourceGroupName -WtpUser $WtpUser

# set the service plan used by all tenants.  Could support venue-specific service plans
$servicePlan = 'standard'

# initialize the batch insert
$batchCommandText = "
    INSERT INTO TenantRequests
        (TenantName, ServicePlan, VenueType, Location, Requested, RequestState, LastUpdated)
    VALUES " 

$batchSize = 0
$i = 1

foreach ($newTenant in $NewTenants)
{
    $newTenantName = $newTenant[0].Trim()
    $newTenantVenueType = $newTenant[1].Trim() 

    # Validate tenant name
    Test-LegalName $newTenantName > $null
    Test-LegalVenueTypeName $newTenantVenueType > $null

    # Compute the tenant key from the tenant name 
    $tenantKey = Get-TenantKey -TenantName $newTenantName 

    # Check if a tenant with this key is aleady registered in the catalog
    if (Test-TenantKeyInCatalog -Catalog $catalog -TenantKey $tenantKey)
    {
        Write-Output "A tenant with name '$newTenantName' is already registered in the catalog. Skipping..."
        continue    
    }
    else
    {
        # verify if there is a pending request for the same tenant        
        $commandText = "
            SELECT Count(TenantName) AS Count FROM TenantRequests
            WHERE TenantName = '$newTenantName' AND RequestState = 'submitted'"

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
            Write-Output "New tenant request already exists for '$newTenantName'. Skipping..."
            continue
        }
     
        if ($i -gt 1) 
        { 
            $batchCommandText += ",`n" 
        }

        $batchCommandText += "('$newTenantName','$ServicePlan','$newTenantVenueType','$Location', CURRENT_TIMESTAMP, 'submitted', CURRENT_TIMESTAMP)"
        $batchSize ++
        
        $i ++ 
    }
} 

if ($batchSize -gt 0)
{
    # insert the batch of requests
    Invoke-SqlAzureWithRetry `
        -ServerInstance $Catalog.FullyQualifiedServerName `
        -Username $config.TenantAdminuserName `
        -Password $config.TenantAdminPassword `
        -Database $Catalog.Database.DatabaseName `
        -Query $batchCommandText `
        -ConnectionTimeout 30 `
        -QueryTimeout 30 
}

$end = Get-Date

Write-Output "$($batchSize) new tenant databases requests submitted."
write-output "Duration $(($end - $start).Minutes) minutes $(($end - $start).seconds) seconds"