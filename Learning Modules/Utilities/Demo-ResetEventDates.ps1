<# Helper script for resetting event dates for all tenants.
    The pre-provisioned tenants and the golden tenant database have events pre-defined on predefined dates. Use this script 
    to reset the event and ticket purchase dates for all tenants. 
#>
Import-Module "$PSScriptRoot\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\UserConfig" -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription -NoEcho

# Get the resource group and user names used when the WTP application was deployed from UserConfig.psm1.  
$wtpUser = Get-UserConfig
   
### Reset event and ticketpurchase dates for all tenants
& $PSScriptRoot\Reset-EventDatesForAllTenants.ps1 `
    -WtpResourceGroupName $wtpUser.ResourceGroupName `
    -WtpUser $wtpUser.Name
#>