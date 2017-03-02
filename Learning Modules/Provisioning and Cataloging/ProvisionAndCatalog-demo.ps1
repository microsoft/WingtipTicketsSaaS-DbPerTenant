# Helper script for demonstrating Deploy-TenantDatabase script, which deploys and registers a new WTP tenant database.

# Get Azure credentials
<#
    Login-AzureRMAccount 
 
    # Set the Azure subscription, needed if your Microsoft account is associated with multiple subscriptions  <<< ***
    
    # use name...
    #$AzureSubscriptionName = '<your subscription name>'
    #$Subscription = Get-AzureRMSubscription -SubscriptionName $AzureSubscriptionName | Select-AzureRMSubscription
    
    # or subscription id...
    $AzureSubscriptionId = '112900e0-ad0e-4ab8-aea2-b09a07253f30' 
    $Subscription = Get-AzureRMSubscription -SubscriptionId $AzureSubscriptionId | Select-AzureRMSubscription
#>

# The resource group name used during the deployment of the WTP app
$ResourceGroupName = "wingtip-bgtickets"

# The 'User' value that was entered during the deployment of the WTP app
$WTPUser = "bgtickets"

# The name of the tenant being provisioned
$TenantName = "Venue" + "-" + ([DateTime]::UtcNow).ToString('yyyy-MM-ddTHH-mm-ssZ')

. $PSScriptRoot\Deploy-TenantDatabase.ps1 -WtpResourceGroupName $ResourceGroupName -WtpUser $WtpUser -TenantName $TenantName