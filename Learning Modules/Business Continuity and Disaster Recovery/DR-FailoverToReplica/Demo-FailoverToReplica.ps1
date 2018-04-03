# Helper script for exploring SaaS app disaster recovery using geo-replication functionality

# The script showcases DR use cases:
#  1. Restore the app into a secondary recovery region by failing over to replicas,
#  2. Repatriate the SaaS app into its original region using geo-replication

## ---------------  PARAMETERS ----------------------------------------------------------------------

$DemoScenario = 1
<# Select the scenario that will be run. Run the scenarios below in order. 
   Scenario
      1     Start a background job that syncs tenant server, and pool configuration info into the catalog
      2     Create mirror image recovery environment and replicate catalog and tenant databases
      3     Recover the app into a recovery region by failing over to replicas
      4     Provision a new tenant in the recovery region 
      5     Delete an event from a tenant in the recovery region
      6     Repatriate the app into its original region
#>

# Parameters for scenario #4, provision a tenant in the recovery region 
$TenantName = "Hawthorn Hall" # name of the venue to be added/removed as a tenant
$VenueType  = "multipurpose"  # valid types: blues, classicalmusic, dance, jazz, judo, motorracing, multipurpose, opera, rockmusic, soccer

# Parameters for scenario #5, delete an event from a tenant in the recovery region
$TenantName2 = "Contoso Concert Hall" # Name of tenant from which event will be deleted

## --------------- INITIALIZATION ------------------------------------------------------------------

Import-Module "$PSScriptRoot\..\..\Common\CatalogAndDatabaseManagement" -Force
Import-Module "$PSScriptRoot\..\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\..\UserConfig" -Force
Import-Module "$PSScriptRoot\..\..\WtpConfig" -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription

# Get the resource group and user names used when the application was deployed  
$wtpUser = Get-UserConfig
$config = Get-Configuration

## --------------- SCENARIOS -----------------------------------------------------------------------

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


### Replicate SaaS app and databases to recovery region
if ($DemoScenario -eq 2)
{
  # Save login credentials for background job
  Save-AzureRmContext -Path "$env:TEMP\profile.json" -Force 
  
  # Start background process
  Start-Process powershell.exe -ArgumentList "-NoExit &'$PSScriptRoot\Deploy-WingtipTicketsReplica.ps1'"

  Write-Output "Creating replica for '$($wtpUser.ResourceGroupName)' Wingtip deployment. This may take several minutes ..."   
     
  exit
}


### Failover SaaS app and databases to recovery region 
if ($DemoScenario -eq 3)
{
  # Save login credentials for background job
  Save-AzureRmContext -Path "$env:TEMP\profile.json" -Force 
  
  # Start background process
  Start-Process powershell.exe -ArgumentList "-NoExit &'$PSScriptRoot\Failover-IntoRecoveryRegion.ps1'"

  Write-Output "Starting failover of application to recovery region ..."  
 
  exit
}

### Provision a new tenant in the recovery region
if ($DemoScenario -eq 4)
{
    # Set up the server and pool names in which the tenant will be provisioned.
    # The server name is retrieved from an alias used to switch between normal and recovery regions 
    $newTenantAlias = $config.NewTenantAliasStem + $wtpUser.Name + ".database.windows.net"
    $serverName = Get-ServerNameFromAlias $newTenantAlias
    $poolName = $config.TenantPoolNameStem + "1"
    $resourceGroupName = (Find-AzureRmResource -ResourceNameEquals $serverName -ResourceType "Microsoft.sql/servers").ResourceGroupName
    try
    {
        New-Tenant `
            -WtpResourceGroupName $resourceGroupName `
            -WtpUser $wtpUser.Name `
            -TenantName $TenantName `
            -ServerName $serverName `
            -PoolName $poolName `
            -VenueType $VenueType `
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

### Delete an event from a tenant
if ($DemoScenario -eq 5)
{
  & $PSScriptRoot\..\..\Utilities\Remove-UnsoldEventFromTenant.ps1 `
                      -WtpResourceGroupName $wtpUser.ResourceGroupName `
                      -WtpUser $wtpUser.Name `
                      -TenantName $TenantName2 `
                      -NoEcho `
                      > $null
  exit
}

### Repatriate the app into its original region
if ($DemoScenario -eq 6)
{
  # Save login credentials for background job
  Save-AzureRmContext -Path "$env:TEMP\profile.json" -Force 
  
  # Start background process
  Start-Process powershell.exe -ArgumentList "-NoExit &'$PSScriptRoot\Repatriate-IntoOriginalRegion.ps1'"
  
  Write-Output "Repatriating app into original region. This may take several minutes..."  
  
  exit
}

### Invalid option selected
Write-Output "Invalid scenario selected"

