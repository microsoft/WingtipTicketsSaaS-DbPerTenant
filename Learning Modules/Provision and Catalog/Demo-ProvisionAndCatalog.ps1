# Helper script for demonstrating Deploy-TenantDatabase script, which deploys and registers a new WTP tenant database.

Import-Module $PSScriptRoot\..\Common\SubscriptionManagement -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription

# Before provisioning any tenants ensure the catalog is initialized using  http://demo.wtp.<user>.traffcimanager.net > Setup

# The resource group name used during the deployment of the WTP app (case sensitive). Replace <resourcegroup>
$WtpResourceGroupName = "<resourcegroup>"

# The 'User' value that was entered during the deployment of the WTP app. Replace <user>
$WtpUser = "<user>"

# The name of the venue to be added as a WTP tenant 
$TenantName = "Venue Name"

# Provision a single tenant
. $PSScriptRoot\New-Tenant.ps1 `
    -WtpResourceGroupName $WtpResourceGroupName `
    -WtpUser $WtpUser `
    -TenantName $TenantName
#>
