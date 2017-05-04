# Helper script for exploring the Restore Tenant scenario.
# The script showcases two restore use cases:
#  1. Restore a tenant in parallel (suited for compliance/auditing),
#  2. Restore a tenant in place (suited for 'oops' recovery)

Import-Module "$PSScriptRoot\..\..\Common\CatalogAndDatabaseManagement" -Force
Import-Module "$PSScriptRoot\..\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\..\UserConfig" -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription

# Get the resource group and user names used when the WTP application was deployed from UserConfig.psm1.  
$wtpUser = Get-UserConfig

# The name of the tenant whose data will be restored 
$TenantName = "Contoso Concert Hall"

$DemoScenario = 0
<# Select the demo scenario that will be run. It is recommended you run the scenarios below in order. 
     Demo   Scenario
      0       None
      1       Delete events with no ticket sales (make sure tickets are bought first)
      2       Restore a tenant in parallel 
      3       Remove a restored tenant database 
      4       Restore a tenant in place
#>

## ------------------------------------------------------------------------------------------------

### Default state - enter a valid demo scenaro 
if ($DemoScenario -eq 0)
{
  Write-Output "Please modify the demo script to select a scenario to run."
  exit
}

### Delete events that have no ticket sales from a specified tenant venue 
if ($DemoScenario -eq 1)
{
  # Open the events page for the venue to track any changes that happen to the event listing 
  Start-Process "http://events.wtp.$($wtpUser.Name).trafficmanager.net/$(Get-NormalizedTenantName $TenantName)"

  # Record point in time before deletion to enable the database to be restored later to an earlier point(in UTC time) 
  $restorePoint = (Get-Date).AddMinutes(-5).ToUniversalTime()

  Write-Output "Deleting unsold events from $TenantName ..."

  # Delete one or more events in a venue. You can verify the event has been deleted by refreshing the events page in your browser
  $deletedEvent = & $PSScriptRoot\..\..\Utilities\Remove-UnsoldEventFromTenant.ps1 `
                    -WtpResourceGroupName $wtpUser.ResourceGroupName `
                    -WtpUser $wtpUser.Name `
                    -TenantName $TenantName `
                    -NoEcho
  
  exit
}


### Restore a tenant in parallel 
if ($DemoScenario -eq 2)
{
  Write-Output "Running 'Restore tenant in parallel' scenario ..."

  # Exit script if an event has not been deleted
  if (!($restorePoint -and $deletedEvent))
  {
    Write-Output "No restore point selected. Please run the 'delete unsold events' scenario."
    exit
  }

  # Restores the tenant as <tenantname>_old and register it in the catalog
  & $PSScriptRoot\Restore-TenantInParallel.ps1 `
      -WtpResourceGroupName $wtpUser.ResourceGroupName `
      -WtpUser $wtpUser.Name `
      -TenantName $TenantName `
      -RestorePoint $restorePoint `
      -NoEcho

  # Open the events page for the restored venue
  Start-Process "http://events.wtp.$($wtpUser.Name).trafficmanager.net/$(Get-NormalizedTenantName $TenantName)_old"

  Write-Output "'$deletedEvent' event restored to $TenantName"
  exit
}


### Remove a previously restored tenant 
if ($DemoScenario -eq 3)
{
  Write-Output "Running 'Remove restored tenant' scenario ..."  

  # Remove the restored database when the tenant has finished using it
  & $PSScriptRoot\..\..\Utilities\Remove-RestoredTenant.ps1 `
     -WtpResourceGroupName $wtpUser.ResourceGroupName `
     -WtpUser $wtpUser.Name `
     -TenantName $TenantName `
     -NoEcho
  exit
}


### Restore a tenant in place 
if ($DemoScenario -eq 4)
{
  Write-Output "Running 'Restore tenant in place scenario ..."

  # Exit script if an event has not been deleted
  if (!($restorePoint -and $deletedEvent))
  {
    Write-Output "No restore point selected. Please run the 'delete unsold events' scenario."
    exit
  }

  # Restore the tenant in place with its current name, and deletes the previous active tenant database. 
  # Further restore operations are available from the deleted database backup chain.
  & $PSScriptRoot\Restore-TenantInPlace.ps1 `
      -WtpResourceGroupName $wtpUser.ResourceGroupName `
      -WtpUser $wtpUser.Name `
      -TenantName $TenantName `
      -RestorePoint $restorePoint `
      -NoEcho

  # Open the events page for the restored venue
  Start-Process "http://events.wtp.$($wtpUser.Name).trafficmanager.net/$(Get-NormalizedTenantName $TenantName)"

  Write-Output "'$deletedEvent' event restored to $TenantName"
  exit
}

### Invalid option selected
Write-Output "Invalid scenario selected"

