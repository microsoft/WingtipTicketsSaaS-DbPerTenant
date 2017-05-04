# Helper script for running the ticket generator.  Requires no input other than setting UserConfig.psm1

Import-Module "$PSScriptRoot\..\Common\SubscriptionManagement"
Import-Module "$PSScriptRoot\..\UserConfig" -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription -NoEcho

# Get the resource group and user names used when the WTP application was deployed from UserConfig.psm1.  
$wtpUser = Get-UserConfig

### (Re)generate tickets for all tenants.  The last event in each tenant will have no tickets and can be deleted.
& $PSScriptRoot\TicketGenerator2.ps1 `
    -WtpResourceGroupname $WtpUser.ResourceGroupName `
    -WtpUser $WtpUser.Name
