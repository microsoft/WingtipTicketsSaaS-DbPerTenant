<#
.SYNOPSIS
  Repatriates the Wingtip SaaS app environment from a recovery region into the original region 

.DESCRIPTION
  This script repatriates the Wingtip SaaS app environment (apps, databases, servers e.t.c) back into the original region from the recovery region.
  It is assumed that when the original region becomes available, the previous resources that were there still exist, but are out of date.
  To bring these resources up to date, this script creates geo-replicas of tenant databases in the original region and syncs the updated data from the recovery region. 

.PARAMETER NoEcho
  Stops the default message output by Azure when a user signs in. This prevents double echo

.EXAMPLE
  [PS] C:\>.\Repatriate-IntoOriginalRegion.ps1
#>
[cmdletbinding()]
param (   
    [parameter(Mandatory=$false)]
    [switch] $NoEcho
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
Initialize-Subscription -NoEcho:$NoEcho.IsPresent

# Get location of primary region
$primaryLocation = (Get-AzureRmResourceGroup -ResourceGroupName $wtpUser.ResourceGroupName).Location
$regionPairs = Get-Content -raw "$PSScriptRoot\..\..\Utilities\AzurePairedRegions.txt" | ConvertFrom-StringData
$recoveryLocation = $regionPairs[$primaryLocation]

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

# Start background process to sync tenant server, pool, and database configuration info into the catalog 
$runningScripts = (Get-WmiObject -Class Win32_Process -Filter "Name='PowerShell.exe'").CommandLine
if (!($runningScripts -like "*Sync-TenantConfiguration*"))
{
  Start-Process powershell.exe -ArgumentList "-NoExit &'$PSScriptRoot\Sync-TenantConfiguration.ps1'"
}

# Cancel tenant restore operations that are still in-flight.
Write-Output "Stopping any pending restore operations ..."
Stop-TenantRestoreOperations -Catalog $catalog 

# Check if active catalog is in recovery region
# Note: This assumes that the DNS alias for the catalog server is only updated during the process of recovery.
if ($catalog.Database.ResourceGroupName -ne $recoveryResourceGroupName)
{
  Write-Output "Resetting catalog database and traffic manager endpoint to origin ..."
  Reset-TrafficManagerEndpoints
}
else
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
    $catalogFailoverGroupName = $config.CatalogServerNameStem + "group" + $wtpUser.Name

    $catalogFailoverGroup = Get-AzureRmSqlDatabaseFailoverGroup `
                              -ResourceGroupName $wtpUser.ResourceGroupName `
                              -ServerName $originCatalogServerName `
                              -FailoverGroupName $catalogFailoverGroupName `
                              -ErrorAction SilentlyContinue
    
    # Failover catalog databases to origin (if applicable)
    if ($catalogFailoverGroup -and ($catalogFailoverGroup.ReplicationRole -eq 'Secondary'))
    {
      Write-Output "Failing over catalog database to origin ..."
      Switch-AzureRmSqlDatabaseFailoverGroup `
        -ResourceGroupName $wtpUser.ResourceGroupName `
        -ServerName $originCatalogServerName `
        -FailoverGroupName $catalogFailoverGroupName `
        >$null

    }
    # Create catalog failover group if it doesn't exist and failover to origin
    else
    {
      # Delete origin catalog databases (idempotent)
      Remove-AzureRmSqlDatabase -ResourceGroupName $wtpUser.ResourceGroupName -ServerName $originCatalogServerName -DatabaseName $config.CatalogDatabaseName -ErrorAction SilentlyContinue
      Remove-AzureRmSqlDatabase -ResourceGroupName $wtpUser.ResourceGroupName -ServerName $originCatalogServerName -DatabaseName $config.GoldenTenantDatabaseName -ErrorAction SilentlyContinue

      # Create failover group for catalog databases
      $catalogFailoverGroup = New-AzureRMSqlDatabaseFailoverGroup `
                                -ResourceGroupName $recoveryResourceGroupName `
                                -FailoverGroupName $catalogFailoverGroupName ` 
                                -ServerName $recoveryCatalogServerName `
                                -PartnerResourceGroupName $wtpUser.ResourceGroupName `
                                -PartnerServerName $originCatalogServerName `
                                -FailoverPolicy Manual

      $catalogDatabases = Get-AzureRmSqlDatabase -ResourceGroupName $recoveryResourceGroupName -ServerName $recoveryCatalogServerName | Where-Object{$_.DatabaseName -ne 'master'}
      $catalogFailoverGroup = $catalogFailoverGroup | Add-AzureRmSqlDatabaseToFailoverGroup -Database $catalogDatabases

      # Failover catalog databases to origin
      Write-Output "Failing over catalog database to origin ..."
      Switch-AzureRmSqlDatabaseFailoverGroup `
        -ResourceGroupName $wtpUser.ResourceGroupName `
        -ServerName $originCatalogServerName `
        -FailoverGroupName $catalogFailoverGroupName `
        >$null
    }   
        
    # Update catalog alias to origin (if applicable)
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
  
  # Enable traffic manager endpoint in origin, disable endpoint in recovery
  Reset-TrafficManagerEndpoints 
}

# Reconfigure servers and elastic pools in original region to match settings in the recovery region 
Write-Output "Syncing tenant servers and elastic pools in original region ..."
$updateTenantResourcesJob = Start-Job -Name "ReconfigureTenantResources" -FilePath "$PSScriptRoot\RecoveryJobs\Update-TenantResourcesInOriginalRegion.ps1" -ArgumentList @($recoveryResourceGroupName)

# Wait to reconfigure servers and pools in origin regionbefore proceeding
Wait-Job $updateTenantResourcesJob

# Start background job to reset tenant databases that have not been changed in the recovery region 
$resetDbJob = Start-Job -Name "ResetDatabases" -FilePath "$PSScriptRoot\RecoveryJobs\Reset-UnchangedDatabases.ps1" -ArgumentList @($recoveryResourceGroupName)

# Start background job to replicate tenant databases that have been changed in the recovery region to origin region
$replicateDbJob = Start-Job -Name "ReplicateDatabases" -FilePath "$PSScriptRoot\RecoveryJobs\Replicate-ChangedDatabases.ps1" -ArgumentList @($recoveryResourceGroupName)

# Start background job to failover tenant databases that have been replicated to the origin region
$failoverDbJob = Start-Job -Name "FailoverDatabases" -FilePath "$PSScriptRoot\RecoveryJobs\Failover-ChangedDatabases.ps1" -ArgumentList @($recoveryResourceGroupName)

# Start background job to mark tenants online in origin region when all required resources have been restored 
$tenantRecoveryJob = Start-Job -Name "TenantRecovery" -FilePath "$PSScriptRoot\RecoveryJobs\Enable-TenantsAfterRecoveryOperation.ps1" -ArgumentList @($recoveryResourceGroupName)

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
  $replicateDatabaseStatus = Format-JobOutput $replicateDatabaseStatus
  $failoverDatabaseStatus = Format-JobOutput $failoverDatabaseStatus
  $tenantRecoveryStatus = Format-JobOutput $tenantRecoveryStatus
 
  # Output status of repatriation jobs to console
  [PSCustomObject] @{
    RepatriatedTenants = $tenantRecoveryStatus
    ResetDatabases = $resetDatabaseStatus
    RepatriatedDatabases = $failoverDatabaseStatus
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

Write-Output "'$($wtpUser.ResourceGroupName)' deployment repatriated back into '$primaryLocation' region in $($elapsedTime.TotalMinutes) minutes."     



#--- PREVIOUS UPDATES -----------


# Mark non-recovered tenants as online and available in the catalog - tenant data is already available in the original region . 
Write-Output "Marking non-recovered tenants as online and available"
$nonRecoveredTenants = Get-ExtendedTenant -Catalog $catalog | Where-Object {($_.TenantRecoveryState -eq "recovering")}
foreach ($tenant in $nonRecoveredTenants)
{
  # Update recovery state of tenant database 
  Set-ExtendedDatabaseRecoveryState -Catalog $catalog -ServerName $tenant.ServerName -DatabaseName $tenant.DatabaseName -State "resetting"

  $tenantKey = Get-TenantKey -TenantName $tenant.DatabaseName
  Set-TenantOnline -Catalog $catalog -TenantKey $tenantKey

  Set-ExtendedDatabaseRecoveryState -Catalog $catalog -ServerName $tenant.ServerName -DatabaseName $tenant.DatabaseName -State "complete"
}

# Monitor state of sync background jobs 
$timeInterval = 10
while ($true)
{
  $updateResourceStatus = Receive-Job -Job $updateTenantResourcesJob -Keep -ErrorAction Stop 
  $newTenantProvisioningStatus = Receive-Job -Job $newTenantProvisioningJob -Keep -ErrorAction Stop 

  # Initialize and format output for update tenant resources job 
  if (!$updateResourceStatus)
  {
    $updateResourceStatus = '--'
  }
  elseif ($updateResourceStatus.Count -gt 1)
  {
    # Display most recent job status 
    $updateResourceStatus = $updateResourceStatus[-1]
  }

  # Initialize and format output for new tenant provisioning job 
  if (!$newTenantProvisioningStatus)
  {
    $newTenantProvisioningStatus = '--'    
  }
  elseif ($newTenantProvisioningStatus.Count -gt 1)
  {
    # Display most recent job status 
    $newTenantProvisioningStatus = $newTenantProvisioningStatus[-1]
  }

  # Output status of sync jobs to console
  [PSCustomObject] @{
    SyncExistingServersPools = $updateResourceStatus
    NewTenantResources = $newTenantProvisioningStatus
  } | Format-List

  # Exit recovery if sync jobs complete 
  if (($updateTenantResourcesJob.State -eq "Completed") -and ($newTenantProvisioningJob.State -eq "Completed"))
  {
    break
  }
  else
  {
    # Sleep for 'timeInterval' seconds 
    Write-Output "---`nRefreshing status in $timeInterval seconds..."
    Start-Sleep $timeInterval
    $elapsedTime = (Get-Date) - $startTime
  }
}

$registeredTenants = Get-Tenants -Catalog $catalog 
$resetToOriginalRegion = $null

# Check if any tenant data has been modified in recovery region 
Write-Output "Checking tenant databases for any changes..."
foreach ($tenant in $registeredTenants)
{
  $tenantDataUpdated = Test-IfTenantDataChanged -Catalog $catalog -TenantName $tenant.Name -ErrorAction Stop
  
  if ($tenantDataUpdated)
  {
    $resetToOriginalRegion = $false    
  }
  # Reset tenant database to original region if there are no changes detected in recovery region 
  else
  {
    $resetToOriginalRegion = $true 
    $tenantObject = Get-Tenant -Catalog $catalog -TenantName $tenant.Name
    Set-ExtendedDatabaseRecoveryState -Catalog $catalog -ServerName $tenantObject.Database.ServerName -DatabaseName $tenantObject.Database.DatabaseName -State "resetting"
    Set-ExtendedTenantRecoveryState -Catalog $catalog -TenantKey $tenantObject.Key -State "resetting"  
    
    # Switch tenant alias to point to database in original region 
    $originServerName = ($tenantObject.Database.ServerName -split $config.RecoverySuffix)[0]
    $tenantServerAlias = ($tenantObject.Alias -split ".database.windows.net")[0] 
    $tenantAlias = Set-AzureRmSqlServerDNSAlias `
                      -ResourceGroupName $wtpUser.ResourceGroupName `
                      -ServerDNSAliasName $tenantServerAlias `
                      -NewServerName $originServerName `
                      -OldServerName $tenantObject.Database.ServerName `
                      -OldServerSubscriptionId $currentSubscriptionId `
                      -OldServerResourceGroup $recoveryResourceGroupName `
                      -ErrorAction Stop 

    # Mark recovery as complete for tenant 
    Set-ExtendedDatabaseRecoveryState -Catalog $catalog -ServerName $originServerName -DatabaseName $tenantObject.Database.DatabaseName -State "complete"
    Set-ExtendedDatabaseRecoveryState -Catalog $catalog -ServerName $tenantObject.Database.ServerName -DatabaseName $tenantObject.Database.DatabaseName -State "complete"
    Set-ExtendedTenantRecoveryState -Catalog $catalog -TenantKey $tenantObject.Key -State "complete" 
  }
}

# Reset traffic manager and apps if no tenant data has been changed in recovery region 
if ($resetToOriginalRegion)
{
  Write-Output "Resetting Wingtip environment to original region ..."
  $profileName = $config.PrimaryEventsAppNameStem + $wtpUser.Name
  $primaryRegionEndpointName = $config.PrimaryEventsAppNameStem + $wtpUser.Name 
  $recoveryRegionEndpointName = $config.PrimaryEventsAppNameStem + $wtpUser.Name + $config.RecoverySuffix

  # Turn on traffic to original region
  Write-Output "Enabling traffic manager endpoint for Wingtip events app in original region ..."
  Enable-AzureRmTrafficManagerEndpoint -Name $primaryRegionEndpointName -Type AzureEndpoints -ProfileName $profileName -ResourceGroupName $wtpUser.ResourceGroupName -ErrorAction Stop > $null 

  # Turn off traffic manager to secondary region 
  Write-Output "Disabling traffic manager endpoint for Wingtip events app in secondary region ..."
  Disable-AzureRmTrafficManagerEndpoint -Name $recoveryRegionEndpointName -Type AzureEndpoints -ProfileName $profileName -ResourceGroupName $wtpUser.ResourceGroupName -Force -ErrorAction Stop > $null

  # Output elapsed time   
  $elapsedTime = (Get-Date) - $startTime
  Write-Output "'$($wtpUser.ResourceGroupName)' deployment repatriated into '$primaryLocation' region in $($elapsedTime.TotalMinutes) minutes."     
}
# Start repatriation process for changed tenant databases
else
{
  # Create geo-replicas of changed tenant databases. Replicas will be created in the original region
  Write-Output "Replicating tenant databases into original region ..." 
  $replicateTenantDatabasesJob = Start-Job -Name "ReplicateTenantDatabases" -FilePath "$PSScriptRoot\RecoveryJobs\Copy-TenantDatabasesIntoOriginalRegion.ps1" -ArgumentList @($recoveryResourceGroupName)

  # Monitor status of replication job
  while ($true)
  {
    $replicateTenantDatabasesStatus = Receive-Job -Job $replicateTenantDatabasesJob -Keep -ErrorAction Stop 

    # Initialize and format output for replication job 
    if (!$replicateTenantDatabasesStatus)
    {
      $replicateTenantDatabasesStatus = '--'
    }
    elseif ($replicateTenantDatabasesStatus.Count -gt 1)
    {
      # Display most recent job status 
      $replicateTenantDatabasesStatus = $replicateTenantDatabasesStatus[-1]
    } 

    # Output status of job to console
    [PSCustomObject] @{ TenantDatabaseReplication = $replicateTenantDatabasesStatus } | Format-List

    # Exit if repatriation complete 
    if ($replicateTenantDatabasesJob.State -eq "Completed")
    {
      Remove-Item -Path "$env:TEMP\profile.json" -ErrorAction SilentlyContinue
      break
    }
    else
    {
      # Sleep for 'timeInterval' seconds 
      Write-Output "---`nRefreshing status in $timeInterval seconds..."
      Start-Sleep $timeInterval
    }
  } 

  # Failover databases to original region in priority order
  # Until the application is failed back to the original region, as each database is repatriated, the application will incur a higher latency
  $repatriationJobs = @()
  Write-Output "Failover over tenant databases..."
  for ($repatriationJob=0; $repatriationJob -lt $FailoverBatchSize; $repatriationJob++)
  {
    $repatriationJobs+= Start-Job -Name "FailoverTenantDatabases-Job$repatriationJob" -FilePath "$PSScriptRoot\RecoveryJobs\Failover-TenantDatabasesToOriginalRegion.ps1" -ArgumentList @($recoveryResourceGroupName)
  }
   
  $catalogRecoveryServerName = $config.CatalogServerNameStem + $WtpUser + $config.RecoverySuffix
  $catalogOriginServerName = $config.CatalogServerNameStem + $WtpUser
  $catalogAliasName = $config.CatalogServerNameStem + $WtpUser + "-alias"

  # Failover tenant catalog
  $catalogFailover = Set-AzureRmSqlDatabaseSecondary `
                      -ResourceGroupName $recoveryResourceGroupName `
                      -ServerName $catalogRecoveryServerName `
                      -DatabaseName $config.CatalogDatabaseName `
                      -PartnerResourceGroupName $wtpUser.ResourceGroupName `
                      -Failover

  # Switch catalog alias to reflect new location 
  $catalogAlias = Set-AzureRmSqlServerDNSAlias `
                      -ResourceGroupName $wtpUser.ResourceGroupName `
                      -ServerDNSAliasName $catalogAliasName `
                      -NewServerName $catalogOriginServerName `
                      -OldServerName $catalogRecoveryServerName `
                      -OldServerSubscriptionId $currentSubscriptionId `
                      -OldServerResourceGroup $recoveryResourceGroupName `
                      -ErrorAction Stop 

  # Wait for all tenant databases to failover to original region 
  while($true)
  {
    $tenantFailoverComplete = $true 
    foreach ($job in $repatriationJob)
    {
      if ($job.State -ne "Completed")
      {
        $tenantFailoverComplete = $false 
      }
    }

    if ($tenantFailoverComplete)
    {
      break
    }
  }

  # Turn on traffic to original region
  Write-Output "Enabling traffic manager endpoint for Wingtip events app in original region ..."
  Enable-AzureRmTrafficManagerEndpoint -Name $primaryRegionEndpointName -Type AzureEndpoints -ProfileName $profileName -ResourceGroupName $wtpUser.ResourceGroupName -ErrorAction Stop > $null 

  # Turn off traffic manager to secondary region 
  Write-Output "Disabling traffic manager endpoint for Wingtip events app in recovery region ..."
  Disable-AzureRmTrafficManagerEndpoint -Name $recoveryRegionEndpointName -Type AzureEndpoints -ProfileName $profileName -ResourceGroupName $wtpUser.ResourceGroupName -Force -ErrorAction Stop > $null   

  $elapsedTime = (Get-Date) - $startTime
}
 





