# Deploys Log Analytics workspace, enables resource diagnostics on WTP databases and pools
# and adds Azure SQL Analytics solution to the workspace

Import-Module "$PSScriptRoot\..\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\..\UserConfig"

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription -NoEcho

# Get the resource group and user names used when the WTP application was deployed from UserConfig.psm1.  
$wtpUser = Get-UserConfig


### Deploy the WTP Log Analytics workspace (free tier)
& $PSSCriptRoot\Deploy-LogAnalyticsWorkspace.ps1 `
    -WtpResourceGroupName $wtpUser.ResourceGroupName `
    -WtpUser $wtpUser.Name
#>    
      
### Enable diagnostics for all WTP SQL databases and elastic pools       
& $PSScriptRoot\Enable-ResourceDiagnostics.ps1 `
    -WtpResourceGroupName $wtpUser.ResourceGroupName `
    -WtpUser $wtpUser.Name `
    -Update
#>        

### Configure the Azure SQL Analytics solution in the WTP Log Analytics workspace
& $PSSCriptRoot\Add-LogAnalyticsSqlAnalyticsSolution.ps1 `
    -WtpResourceGroupName $wtpUser.ResourceGroupName `
    -WtpUser $wtpUser.Name
#>