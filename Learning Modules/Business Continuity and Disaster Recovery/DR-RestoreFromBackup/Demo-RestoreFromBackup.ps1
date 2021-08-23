# Helper script for exploring SaaS app disaster recovery using geo-restore from backups

# The script showcases two DR use cases:
#  1. Restore the app into a secondary recovery region using geo-restore from automatic backups,
#  2. Repatriate the app into its original region using geo-replication

## ---------------  PARAMETERS ----------------------------------------------------------------------

$DemoScenario = 1
<# Select the scenario that will be run. Run the scenarios below in order. 
   Scenario
      1     Start synchronizing tenant server, pool, and database configuration info into the catalog
      2     Recover the app into a recovery region by restoring from geo-redundant backups
      3     Provision a new tenant in the recovery region 
      4     Delete an event from a tenant in the recovery region
      5     Repatriate the app into its original region
      6     Delete obsolete resources from the recovery region 
#>

# Parameters for scenario #3, provision a tenant in the recovery region 
$TenantName = "Hawthorn Hall" # name of the venue to be added/removed as a tenant
$VenueType  = "multipurpose"  # valid types: blues, classicalmusic, dance, jazz, judo, motorracing, multipurpose, opera, rockmusic, soccer

# Parameters for scenario #4, delete an event from a tenant in the recovery region
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

# Get the Wingtip Tickets app configuration
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


### Recover the app into the recovery region by restoring from geo-redundant backups
if ($DemoScenario -eq 2)
{
  # Save login credentials for background job
  Save-AzureRmContext -Path "$env:TEMP\profile.json" -Force

  Write-Output "`nStarting geo-restore of application. This may take 20 minutes or more..."  
  
  Start-Process powershell.exe -ArgumentList "-NoExit &'$PSScriptRoot\Restore-IntoSecondaryRegion.ps1'"
     
  exit
}


### Provision a new tenant in the recovery region
if ($DemoScenario -eq 3)
{
    # Set up the server and pool names in which the tenant will be provisioned.
    # The server name is retrieved from an alias used to switch between normal and recovery regions 
    $newTenantAlias = $config.NewTenantAliasStem + $wtpUser.Name + ".database.windows.net"
    $serverName = Get-ServerNameFromAlias $newTenantAlias
    $poolName = $config.TenantPoolNameStem + "1"
    $resourceGroupName = (Get-AzureRmResource -Name $serverName -ResourceType "Microsoft.sql/servers").ResourceGroupName
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
#>


### Delete an event from a tenant
if ($DemoScenario -eq 4)
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
if ($DemoScenario -eq 5)
{
  # Save login credentials for background job
  Save-AzureRmContext -Path "$env:TEMP\profile.json" -Force
  
  Write-Output "Repatriating app into original region. This may take several minutes..."

  Start-Process powershell.exe -ArgumentList "-NoExit &'$PSScriptRoot\Repatriate-IntoOriginalRegion.ps1'"

  exit
}

### Delete obsolete resources from the recovery region
if ($DemoScenario -eq 6)
{
  Write-Output "Deleting obsolete recovery resources ..."

  $tenantCatalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name
  $recoveryServerList = Get-ExtendedServer -Catalog $tenantCatalog | Where-Object{$_.ServerName -match "$($config.RecoveryRoleSuffix)$"}
  $recoveryPoolList = Get-ExtendedElasticPool -Catalog $tenantCatalog | Where-Object{$_.ServerName -match "$($config.RecoveryRoleSuffix)$"}
  $recoveryDatabaseList = Get-ExtendedDatabase -Catalog $tenantCatalog | Where-Object{$_.ServerName -match "$($config.RecoveryRoleSuffix)$"}
  Write-Output "Removing recovery resources from the catalog ..."

  # Remove recovery server entries from the catalog
  foreach($recoveryserver in $recoveryServerList)
  {
    Remove-ExtendedServer -Catalog $tenantCatalog -ServerName $recoveryserver.ServerName > $null
  }

  # Remove recovery elastic pool entries from the catalog
  foreach($recoverypool in $recoveryPoolList)
  {
    Remove-ExtendedElasticPool -Catalog $tenantCatalog -ServerName $recoverypool.ServerName -ElasticPoolName $recoverypool.ElasticPoolName > $null
  }

  # Remove recovery database entires from the catalog
  foreach($recoverydatabase in $recoveryDatabaseList)
  {
    Remove-ExtendedDatabase -Catalog $tenantCatalog -ServerName $recoverydatabase.ServerName -DatabaseName $recoverydatabase.DatabaseName > $null
  }   

  Write-Output "Deleting recovery resources in Azure ..."
  $recoveryResourceGroupName = $wtpUser.ResourceGroupName + $config.RecoveryRoleSuffix
  Remove-AzureRmResourceGroup -Name $recoveryResourceGroupName -Force -ErrorAction SilentlyContinue > $null
  exit
}

### Invalid option selected
Write-Output "Invalid scenario selected"