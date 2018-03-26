<#
.SYNOPSIS
  Repatriates the Wingtip SaaS app environment from a recovery region into the original region 

.DESCRIPTION
  This script repatriates the Wingtip SaaS app environment (apps, databases, servers e.t.c) back into the original region from the recovery region.
  It is assumed that when the original region becomes available, the previous resources that were there still exist, but are out of date.
  To bring these resources up to date, this script creates geo-replicas of tenant databases in the original region and syncs the updated data from the recovery region. 

.PARAMETER NoEcho
  Stops the default message output by Azure when a user signs in. This prevents double echo

.PARAMETER StatusCheckTimeInterval
  This determines how often the script will check on the status of background recovery jobs. The script will wait the provided time in seconds before checking the status again.

.EXAMPLE
  [PS] C:\>.\Repatriate-IntoOriginalRegion.ps1
#>
[cmdletbinding()]
param (   
    [parameter(Mandatory=$false)]
    [switch] $NoEcho,

    [parameter(Mandatory=$false)]
    [Int] $StatusCheckTimeInterval = 10
)

#----------------------------------------------------------[Initialization]----------------------------------------------------------

Import-Module $PSScriptRoot\..\..\Common\CatalogAndDatabaseManagement -Force
Import-Module $PSScriptRoot\..\..\Common\FormatJobOutput -Force
Import-Module $PSScriptRoot\..\..\WtpConfig -Force
Import-Module $PSScriptRoot\..\..\UserConfig -Force

# Get deployment configuration  
$wtpUser = Get-UserConfig
$config = Get-Configuration
$currentSubscriptionId = Get-SubscriptionId

# Get Azure credentials if not already logged on
$credentialLoad = Import-AzureRmContext -Path "$env:TEMP\profile.json"
if (!$credentialLoad)
{
    Initialize-Subscription -NoEcho:$NoEcho.IsPresent
}
else
{
  $AzureContext = Get-AzureRmContext
  $subscriptionId = Get-SubscriptionId
  $subscriptionName = Get-SubscriptionName
  Write-Output "Signed-in as $($AzureContext.Account), Subscription '$($subscriptionId)' '$($subscriptionName)'"    
}

# Get location of primary region
$primaryLocation = (Get-AzureRmResourceGroup -ResourceGroupName $wtpUser.ResourceGroupName).Location

# Get location of recovery region 
$content = Get-Content "$PSScriptRoot\..\..\Utilities\AzurePairedRegions.txt" | Out-String
$regionPairs = Invoke-Expression $content
$recoveryLocation = $regionPairs.Item($primaryLocation)

# Get the active tenant catalog 
$catalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name
$recoveryResourceGroupName = $wtpUser.ResourceGroupName + $config.RecoveryRoleSuffix 

#------------------------------------------------------[Helper Functions]-------------------------------------------------------
<#
 .SYNOPSIS  
  Disables traffic manager endpoint in the recovery region if it exists, and enables the endpoint in the origin region.
  This function also updates the tenant provisioning DNS alias to point to the appropriate tenant server in the origin region.
#>
function Reset-TrafficManagerEndpoints
{
  # Enable traffic manager endpoint in origin
  $profileName = $config.EventsAppNameStem + $wtpUser.Name
  $endpointName = $config.EventsAppNameStem + $primaryLocation + '-' + $wtpUser.Name
  $webAppEndpoint = Get-AzureRmTrafficManagerEndpoint -Name $endpointName -Type AzureEndpoints -ProfileName $profileName -ResourceGroupName $wtpUser.ResourceGroupName
    
  if ($webAppEndpoint.EndpointStatus -ne 'Enabled')
  {
    Write-Output "Enabling traffic manager endpoint for Wingtip events app in origin '$endpointName' ..."
    Enable-AzureRmTrafficManagerEndpoint -Name $endpointName -Type AzureEndpoints -ProfileName $profileName -ResourceGroupName $wtpUser.ResourceGroupName -ErrorAction Stop > $null
  }

  # Disable traffic manager endpoint in recovery region (if applicable)
  $recoveryAppEndpointName = $config.EventsAppNameStem + $recoveryLocation + '-' + $wtpUser.Name
  $recoveryAppEndpoint = Get-AzureRmTrafficManagerEndpoint -Name $recoveryAppEndpointName -Type AzureEndpoints -ProfileName $profileName -ResourceGroupName $wtpUser.ResourceGroupName -ErrorAction SilentlyContinue
  if ($recoveryAppEndpoint -and $recoveryAppEndpoint.EndpointStatus -ne 'Disabled')
  {
    Write-Output "Disabling traffic manager endpoint for Wingtip events app in recovery region '$recoveryAppEndpointName' ..."
    Disable-AzureRmTrafficManagerEndpoint -Name $recoveryAppEndpointName -Type AzureEndpoints -ProfileName $profileName -ResourceGroupName $wtpUser.ResourceGroupName -Force -ErrorAction SilentlyContinue > $null
  }

  # Update tenant provisioning server alias to point to original location (if applicable)
  $newTenantAlias = $config.NewTenantAliasStem + $wtpUser.Name
  $fullyQualifiedNewTenantAlias = $newTenantAlias + ".database.windows.net"
  $originProvisioningServerName = $config.TenantServerNameStem + $wtpUser.Name
  $currentProvisioningServerName = Get-ServerNameFromAlias $fullyQualifiedNewTenantAlias

  if ($currentProvisioningServerName -ne $originProvisioningServerName)
  {
    Write-Output "Updating DNS alias for new tenant provisioning ..."
    Set-DnsAlias `
        -ResourceGroupName $wtpUser.ResourceGroupName `
        -ServerName $originProvisioningServerName `
        -ServerDNSAlias $newTenantAlias `
        -OldResourceGroupName $recoveryResourceGroupName `
        -OldServerName $currentProvisioningServerName `
        -PollDnsUpdate `
        >$null
  }
}

#-------------------------------------------------------[Main Script]------------------------------------------------------------

$startTime = Get-Date

# Initialize variables for background jobs 
$scriptPath= $PSScriptRoot
Save-AzureRmContext -Path "$env:TEMP\profile.json" -Force -ErrorAction Stop

# Cancel tenant restore operations that are still in-flight.
Write-Output "Stopping any pending restore operations ..."
Stop-TenantRestoreOperations -Catalog $catalog 

# Check if active catalog is in recovery region
# Note: This assumes that the DNS alias for the catalog server is only updated during the process of recovery.
if ($catalog.Database.ResourceGroupName -ne $recoveryResourceGroupName)
{
  Write-Output "Catalog database already failed over to origin. Resetting traffic manager endpoint to origin ..."
  Reset-TrafficManagerEndpoints
}

# Reconfigure servers and elastic pools in original region to match settings in the recovery region 
Write-Output "Reconfiguring tenant servers and elastic pools in original region to match recovery region ..."
$updateTenantResourcesJob = Start-Job -Name "ReconfigureTenantResources" -FilePath "$PSScriptRoot\RecoveryJobs\Update-TenantResourcesInOriginalRegion.ps1" -ArgumentList @($recoveryResourceGroupName)

# Start background job to reset tenant databases that have not been changed in the recovery region 
$resetDbJob = Start-Job -Name "ResetDatabases" -FilePath "$PSScriptRoot\RecoveryJobs\Reset-UnchangedDatabases.ps1" -ArgumentList @($recoveryResourceGroupName)

# Wait to reconfigure servers and pools in origin region before proceeding
$reconfigureJobStatus = Wait-Job $updateTenantResourcesJob
if ($reconfigureJobStatus.State -eq "Failed")
{
  Receive-Job $updateTenantResourcesJob
  exit
}

# Wait till all tenant databases that have not been changed in the recovery region are reset
$resetDbJobStatus = Wait-Job $resetDbJob
if ($resetDbJobStatus.State -eq "Failed")
{
  Receive-Job $resetDbJob
  exit
}

# Failover the active catalog database to origin (if applicable)
if ($catalog.Database.ResourceGroupName -eq $recoveryResourceGroupName)
{
  $tenantDatabaseList = Get-ExtendedDatabase -Catalog $catalog
  $defaultRecoveryTenantServerName = $config.TenantServerNameStem + $wtpUser.Name + $config.RecoveryRoleSuffix

  # Get list of restored tenant databases
  $restoredDbs = $tenantDatabaseList | Where-Object{$_.RecoveryState -eq 'restored'}

  # Get list of new tenants added in the recovery region
  $newTenants = $tenantDatabaseList | Where-Object{$_.ServerName -ne $defaultRecoveryTenantServerName}

  # Reset catalog to origin if no tenant database has been restored or a new tenant added
  if (($restoredDbs -eq $null) -and ($newTenants -eq $null))
  {
    # Update catalog alias to origin
    $catalogAliasName = $config.ActiveCatalogAliasStem + $wtpUser.Name
    $originCatalogServer = $config.CatalogServerNameStem + $wtpUser.Name
    $activeCatalogServer = Get-ServerNameFromAlias "$catalogAliasName.database.windows.net"
    if ($activeCatalogServer -ne $originCatalogServer)
    {
      Write-Output "Updating active catalog alias to point to origin server '$originCatalogServer' ..."
      Set-DnsAlias `
        -ResourceGroupName $wtpUser.ResourceGroupName `
        -ServerName $originCatalogServer `
        -ServerDNSAlias $catalogAliasName `
        -OldResourceGroupName $recoveryResourceGroupName `
        -OldServerName $activeCatalogServer `
        -PollDnsUpdate `
        >$null
    }    
  }
  # Failover recovery catalog database to origin if it has been modified
  else
  {
    $catalogAliasName = $config.ActiveCatalogAliasStem + $wtpUser.Name
    $originCatalogServerName = $config.CatalogServerNameStem + $wtpUser.Name
    $recoveryCatalogServerName = $config.CatalogServerNameStem + $wtpUser.Name + $config.RecoveryRoleSuffix
    $catalogFailoverGroupName = $config.CatalogFailoverGroupNameStem + $wtpUser.Name

    $catalogFailoverGroup = Get-AzureRmSqlDatabaseFailoverGroup `
                              -ResourceGroupName $wtpUser.ResourceGroupName `
                              -ServerName $originCatalogServerName `
                              -FailoverGroupName $catalogFailoverGroupName `
                              -ErrorAction SilentlyContinue
    
    # Failover catalog databases to origin (if applicable)
    if ($catalogFailoverGroup -and ($catalogFailoverGroup.ReplicationRole -eq 'Secondary') -and ($catalogFailoverGroup.ReplicationState -eq 'CATCH_UP'))
    {
      Write-Output "Failing over catalog database to origin ..."
      Switch-AzureRmSqlDatabaseFailoverGroup `
        -ResourceGroupName $wtpUser.ResourceGroupName `
        -ServerName $originCatalogServerName `
        -FailoverGroupName $catalogFailoverGroupName `
        >$null
    }
    elseif ($catalogFailoverGroup -and ($catalogFailoverGroup.ReplicationRole -eq 'Secondary') -and ($catalogFailoverGroup.ReplicationState -In 'PENDING', 'SEEDING'))
    {
      Write-Output "Catalog database in origin region is still being seeded with data from the recovery region. Try running the repatriation script again later."
      exit 
    }
    # Create catalog failover group if it doesn't exist and failover to origin
    else
    {
      # Delete origin catalog databases (idempotent)
      Remove-AzureRmSqlDatabase -ResourceGroupName $wtpUser.ResourceGroupName -ServerName $originCatalogServerName -DatabaseName ($config.CatalogDatabaseName).ToLower() -ErrorAction SilentlyContinue >$null
      Remove-AzureRmSqlDatabase -ResourceGroupName $wtpUser.ResourceGroupName -ServerName $originCatalogServerName -DatabaseName ($config.GoldenTenantDatabaseName).ToLower() -ErrorAction SilentlyContinue >$null

      # Create failover group for catalog databases
      Write-Output "Creating failover group for databases in catalog server ..."
      $catalogFailoverGroup = New-AzureRmSqlDatabaseFailoverGroup `
                                -FailoverGroupName $catalogFailoverGroupName `
                                -ResourceGroupName $recoveryResourceGroupName `
                                -ServerName $recoveryCatalogServerName `
                                -PartnerResourceGroupName $wtpUser.ResourceGroupName `
                                -PartnerServerName $originCatalogServerName `
                                -FailoverPolicy Manual      

      $catalogDatabases = Get-AzureRmSqlDatabase -ResourceGroupName $recoveryResourceGroupName -ServerName $recoveryCatalogServerName | Where-Object{$_.DatabaseName -ne 'master'}
      Write-Output "Geo-replicating databases in catalog server failover group ..."
      foreach ($database in $catalogDatabases)
      {
        Add-AzureRmSqlDatabaseToFailoverGroup `
          -ResourceGroupName $recoveryResourceGroupName `
          -ServerName $recoveryCatalogServerName `
          -FailoverGroupName $catalogFailoverGroupName `
          -Database $database `
          >$null
      }

      # Failover catalog databases to origin
      Write-Output "Failing over catalog server to origin ..."
      Switch-AzureRmSqlDatabaseFailoverGroup `
        -ResourceGroupName $wtpUser.ResourceGroupName `
        -ServerName $originCatalogServerName `
        -FailoverGroupName $catalogFailoverGroupName `
        >$null
    }   
        
    # Update catalog alias to origin (if applicable)
    $activeCatalogServer = Get-ServerNameFromAlias "$catalogAliasName.database.windows.net"
    if ($activeCatalogServer -ne $originCatalogServerName)
    {
      Write-Output "Updating active catalog alias to point to origin server '$originCatalogServerName' ..."
      Set-DnsAlias `
        -ResourceGroupName $wtpUser.ResourceGroupName `
        -ServerName $originCatalogServerName `
        -ServerDNSAlias $catalogAliasName `
        -OldResourceGroupName $recoveryResourceGroupName `
        -OldServerName $activeCatalogServer `
        -PollDnsUpdate `
        >$null
    }    
  }
  
  # Enable traffic manager endpoint in origin, disable endpoint in recovery
  Reset-TrafficManagerEndpoints  
}

$runningScripts = (Get-WmiObject -Class Win32_Process -Filter "Name='PowerShell.exe'") | Where-Object{$_.CommandLine -like "*Sync-TenantConfiguration*"}
foreach($script in $runningScripts)
{
  $script.Terminate() > $null
}
# Start background process to sync tenant server, pool, and database configuration info into the catalog 
Start-Process powershell.exe -ArgumentList "-NoExit &'$PSScriptRoot\Sync-TenantConfiguration.ps1'"

# Get the active tenant catalog 
$catalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name

# Mark any databases stuck in repatriating state as in error
$databaselist = Get-ExtendedDatabase -Catalog $catalog
foreach ($database in $databaselist)
{
  if ($database.RecoveryState -In 'resetting', 'replicating', 'repatriating')
  {
    $dbState = Update-TenantResourceRecoveryState -Catalog $catalog -UpdateAction "markError" -ServerName $database.ServerName -DatabaseName $database.DatabaseName
  }
}

# Start background job to replicate tenant databases that have been changed in the recovery region to origin region
$replicateDbJob = Start-Job -Name "ReplicateDatabases" -FilePath "$PSScriptRoot\RecoveryJobs\Replicate-ChangedTenantDatabases.ps1" -ArgumentList @($recoveryResourceGroupName)

# Start background job to failover tenant databases that have been replicated to the origin region
$failoverDbJob = Start-Job -Name "FailoverDatabases" -FilePath "$PSScriptRoot\RecoveryJobs\Failover-ChangedDatabases.ps1" -ArgumentList @($recoveryResourceGroupName)

# Start background job to mark tenants online in origin region when all required resources have been restored 
$tenantRecoveryJob = Start-Job -Name "TenantRecovery" -FilePath "$PSScriptRoot\RecoveryJobs\Enable-TenantsAfterRecoveryOperation.ps1" -ArgumentList @($recoveryResourceGroupName, "repatriation")

# Monitor state of all repatriation jobs 
while ($true)
{
  # Get state of all repatriation jobs. Stop repatriation if there is an error with any job
  $resetDatabaseStatus = Receive-Job -Job $resetDbJob -Keep -ErrorAction Stop
  $replicateDatabaseStatus = Receive-Job -Job $replicateDbJob -Keep -ErrorAction Stop
  $failoverDatabaseStatus = Receive-Job -Job $failoverDbJob -Keep -ErrorAction Stop
  $tenantRecoveryStatus = Receive-Job -Job $tenantRecoveryJob -Keep -ErrorAction Stop 

  # Initialize and format output for recovery jobs 
  $resetDatabaseStatus = Format-JobOutput $resetDatabaseStatus
  $failoverDatabaseStatus = Format-JobOutput $failoverDatabaseStatus
  $tenantRecoveryStatus = Format-JobOutput $tenantRecoveryStatus
 
  # Output status of repatriation jobs to console
  [PSCustomObject] @{
    "Unchanged databases reactivated in original region" = $resetDatabaseStatus
    "Databases geo-replicated and failed-over to original region" = $failoverDatabaseStatus
  } | Format-List
  

  # Exit recovery if all tenants have been repatriated to origin 
  if (($resetDbJob.State -eq "Completed") -and ($replicateDbJob.State -eq "Completed") -and ($failoverDbJob.State -eq "Completed") -and ($tenantRecoveryJob.State -eq "Completed"))
  {
    Remove-Item -Path "$env:TEMP\profile.json" -ErrorAction SilentlyContinue   
    break
  }
  else
  {
    Write-Output "---`nRefreshing status in $StatusCheckTimeInterval seconds..."
    Start-Sleep $StatusCheckTimeInterval
    $elapsedTime = (Get-Date) - $startTime
  }          
}
$elapsedTime = [math]::Round($elapsedTime.TotalMinutes,2)
Write-Output "'$($wtpUser.ResourceGroupName)' deployment repatriated back into '$primaryLocation' region in $elapsedTime minutes."     

