# Helper script for exploring SaaS app disaster recovery using geo-restore functionality
# The script showcases two restore use cases:
#  1. Restore the SaaS app into a secondary recovery region,
#  2. Repatriate the SaaS app back into the original region

Import-Module "$PSScriptRoot\..\..\Common\CatalogAndDatabaseManagement" -Force
Import-Module "$PSScriptRoot\..\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\..\UserConfig" -Force
Import-Module "$PSScriptRoot\..\..\WtpConfig" -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription

$DemoScenario = 0
<# Select the demo scenario that will be run. It is recommended you run the scenarios below in order. 
     Demo   Scenario
      0       None
      1       Start a background job that syncs tenant server, pool, and database configuration info into the catalog
      2       Recover the SaaS app into a recovery region by restoring from geo-redundant backups
      3       Repatriate the SaaS app into its original region.
      4       Delete the resources in the recovery region
#>

## ------------------------------------------------------------------------------------------------

### Default state - enter a valid demo scenaro 
if ($DemoScenario -eq 0)
{
  Write-Output "Please modify the demo script to select a scenario to run."
  exit
}

### Sync tenant pool/server configuration into the catalog
if ($DemoScenario -eq 1)
{
  Write-Output "Running 'Tenant configuration sync' in background process ..." 
  
  # Save login credentials for background job
  Save-AzureRmContext -Path "$env:TEMP\profile.json" -Force 
  
  # Start background process
  Start-Process powershell.exe -ArgumentList "-NoExit &'$PSScriptRoot\Sync-TenantConfiguration.ps1'"
  
  exit
}


### Restore SaaS app into secondary region
if ($DemoScenario -eq 2)
{
  Write-Output "Restoring SaaS app into recovery region ..."  
  
  & $PSScriptRoot\Restore-IntoSecondaryRegion.ps1 -NoEcho
     
  exit
}


### Repatriate SaaS app back to primary region
if ($DemoScenario -eq 3)
{
  Write-Output "Repatriating SaaS app into primary region ..."
  
  & $PSScriptRoot\Repatriate-IntoOriginalRegion.ps1 -NoEcho
  
  exit
}


### Delete resources in secondary region
if ($DemoScenario -eq 4)
{
  Write-Output "Deleting recovery resources ..."

  #& $PSScriptRoot\Remove-RecoveryResources.ps1 -NoEcho
 
  exit
}

### Invalid option selected
Write-Output "Invalid scenario selected"

