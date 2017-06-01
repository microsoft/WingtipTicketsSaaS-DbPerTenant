# Deploys a Log Analytics workspace, then enables resource diagnostics on all WTP databases and pools to the workspace
# then adds Azure SQL Analytics solution to the workspace

Import-Module "$PSScriptRoot\..\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\..\UserConfig"

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription -NoEcho

# Get the resource group and user names used when the WTP application was deployed  
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