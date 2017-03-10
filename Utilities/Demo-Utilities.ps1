

Import-Module "$PSScriptRoot\..\Learning Modules\Common\SubscriptionManagement"

# Ensure logged in to Azure
Initialize-Subscription # -Force

# Resource Group Name entered during deployment of the Wingtip SaaS app
$WtpResourceGroupName = "wingtip-<user>"

# The user name used entered during deployment
$WtpUser = "<user>"

. $PSScriptRoot\TicketGenerator.ps1 `
    -WtpResourceGroupname $WtpResourceGroupName `
    -WtpUser $WtpUser

