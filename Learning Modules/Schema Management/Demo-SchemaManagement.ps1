# Helper script for running the ticket generator.  Requires no input other than setting UserConfig.psm1

Import-Module "$PSScriptRoot\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\UserConfig" -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription -NoEcho

# Get the resource group and user names used when the WTP application was deployed from UserConfig.psm1.  
$wtpUser = Get-UserConfig

# Before provisioning any tenants ensure the catalog is initialized using  http://demo.wtp.<user>.traffcimanager.net > Setup

# Provision a job account database and job account
& $PSScriptRoot\Deploy-JobAccount.ps1 `
    -WtpResourceGroupname $WtpUser.ResourceGroupName `
    -WtpUser $WtpUser.Name
    
# Provision the adhoc analytics database
& "$PSScriptRoot\..\Operational Analytics\Adhoc Analytics\Deploy-AdhocAnalyticsDB.ps1" `
    -WtpResourceGroupname $WtpUser.ResourceGroupName `
    -WtpUser $WtpUser.Name