# Helper script for exploring SaaS app disaster recovery using geo-restore from backups

# The script showcases two DR use cases:
#  1. Restore the app into a secondary recovery region using geo-restore from automatic backups,
#  2. Repatriate the app into its original region using geo-replication

# Parameters for scenarios #3, provision a tenant in the recovery region 
$TenantName = "Red Pine Rock" # name of the venue to be added/removed as a tenant
$VenueType  = "rockmusic"      # valid types: blues, classicalmusic, dance, jazz, judo, motorracing, multipurpose, opera, rockmusic, soccer 
$PostalCode = "98052"

$DemoScenario = 1
<# Select the scenario that will be run. It is recommended you run the scenarios below in order. 
   Scenario
      1     Start synchronizing tenant server, pool, and database configuration info into the catalog
      2     Recover the app into a recovery region by restoring from geo-redundant backups
      3     Provision a new tenant in the recovery region 
      4     Delete an event from a tenant in the recovery region
      5     Repatriate the app into its original region
      6     Delete obsolete resources from the recovery region 
#>

# The name of the tenant whose event will be deleted in scenario 3 
$TenantName = "Contoso Concert Hall"

Import-Module "$PSScriptRoot\..\..\Common\CatalogAndDatabaseManagement" -Force
Import-Module "$PSScriptRoot\..\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\..\UserConfig" -Force
Import-Module "$PSScriptRoot\..\..\WtpConfig" -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription

# Get the resource group and user names used when the application was deployed  
$wtpUser = Get-UserConfig

# Get the Wingtip Tickets app configuration
$config = Get-Configuration

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


### Restore app into the recovery region
if ($DemoScenario -eq 2)
{
  Write-Output "Restoring app into recovery region ..."  
  
  & $PSScriptRoot\Restore-IntoSecondaryRegion.ps1 -NoEcho
     
  exit
}


### Provision a new tenant in the recovery region
if ($DemoScenario -eq 3)
{
    # set up the server and pool names in which the tenant will be provisioned
    $newTenantAlias = $config.NewTenantAliasStem + $wtpUser.Name + ".database.windows.net"
    $serverName = Get-ServerNameFromAlias $newTenantAlias
    $poolName = $config.TenantPoolNameStem + "1"
    try
    {
        New-Tenant `
            -WtpResourceGroupName $wtpUser.ResourceGroupName `
            -WtpUser $wtpUser.Name `
            -TenantName $TenantName `
            -ServerName $serverName `
            -PoolName $poolName `
            -VenueType $VenueType `
            -PostalCode $PostalCode `
            -ErrorAction Stop `
            > $null
    }
    catch
    {
        Write-Error $_.Exception.Message
        exit
    }

    Write-Output "Provisioning complete for tenant '$TenantName'"

    # Open the events page for the new venue
    Start-Process "http://events.wingtip-dpt.$($wtpUser.Name).trafficmanager.net/$(Get-NormalizedTenantName $TenantName)"
    
    exit
}
#>


### Delete an event from a tenant
if ($DemoScenario -eq 4)
{
  Write-Output "Restoring  app into recovery region.  This will take several minutes..."  
  
  & $PSScriptRoot\Restore-IntoSecondaryRegion.ps1 -NoEcho
     
  exit
}


### Repatriate the app into its original region
if ($DemoScenario -eq 5)
{
  Write-Output "Repatriating app into primary region. This will take several minutes..."
  
  #& $PSScriptRoot\Repatriate-IntoOriginalRegion.ps1 -NoEcho
  
  exit
}


<### Delete obsolete resources in recovery region
if ($DemoScenario -eq 6)
{
  Write-Output "Deleting recovery resources ..."

  #& $PSScriptRoot\Remove-RecoveryResources.ps1 -NoEcho
 
  exit
}
#>

### Invalid option selected
Write-Output "Invalid scenario selected"

