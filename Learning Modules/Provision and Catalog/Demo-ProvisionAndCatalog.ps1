# Helper script for provisioning and de-provisioning tenants and their databases.

# IMPORTANT: Before provisioning tenants using this script ensure the catalog is initialized using 
# http://demo.wtp.<USER>.trafficmanager.net

# The name of the venue to be added/removed as a tenant 
$TenantName = "Red Maple Racing"

# The type of venue. Needed when adding a tenant 
$VenueType = "motorracing"
# Supported venue types: blues, classicalmusic, dance, jazz, judo, motorracing, multipurpose, opera, rockmusic, soccer 

# Postal Code of the venue
$PostalCode = "98052"

$DemoScenario = 1
<# Select the demo scenario to run
    Demo    Scenario
      1       Provision a single tenant
      2       Remove a provisioned tenant
      3       Provision a batch of tenants
#>

## ------------------------------------------------------------------------------------------------

Import-Module "$PSScriptRoot\..\Common\CatalogAndDatabaseManagement" -Force
Import-Module "$PSScriptRoot\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\WtpConfig" -Force
Import-Module "$PSScriptRoot\..\UserConfig" -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription -NoEcho

# Get the resource group and user names used when the WTP application was deployed from UserConfig.psm1.  
$wtpUser = Get-UserConfig

# get the WTP app configuration
$config = Get-Configuration

### Provision a single tenant
if ($DemoScenario -eq 1)
{
    # set up the server and pool names in which the tenant will be provisioned
    $serverName = $config.TenantServerNameStem + $wtpUser.Name
    $poolName = $config.TenantPoolNameStem + "1"

    New-Tenant `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -WtpUser $wtpUser.Name `
        -TenantName $TenantName `
        -ServerName $serverName `
        -PoolName $poolName `
        -VenueType $VenueType `
        -PostalCode $PostalCode `
        -ErrorAction Stop `
        > $null

    Write-Output "Provisioning complete for tenant '$TenantName'"

    # Open the events page for the new venue
    Start-Process "http://events.wtp.$($wtpUser.Name).trafficmanager.net/$(Get-NormalizedTenantName $TenantName)"
    
    exit
}
#>

### Remove a provisioned tenant
if ($DemoScenario -eq 2)
{
    & $PSScriptRoot\Remove-ProvisionedTenant.ps1 `
       -WtpResourceGroupName $wtpUser.ResourceGroupName `
       -WtpUser $wtpUser.Name `
       -TenantName $TenantName 
    
    exit
}

### Provision a batch of tenants
if ($DemoScenario -eq 3)
{
    $config = Get-Configuration

    $tenantNames = $config.TenantNameBatch

    & $PSScriptRoot\New-TenantBatch.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -WtpUser $wtpUser.Name `
        -NewTenants $tenantNames 

    exit
} 

Write-Output "Invalid scenario selected"
              