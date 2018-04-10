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
$credentialLoad = Import-AzureRmContext -Path "$env:TEMP\profile.json" -ErrorAction SilentlyContinue
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
$catalogAliasName = $config.ActiveCatalogAliasStem + $wtpUser.Name
$originCatalogServerName = $config.CatalogServerNameStem + $wtpUser.Name
$recoveryCatalogServerName = $config.CatalogServerNameStem + $wtpUser.Name + $config.RecoveryRoleSuffix
$catalogFailoverGroupName = $config.CatalogFailoverGroupNameStem + $wtpUser.Name

# Initialize variables for background jobs 
$scriptPath= $PSScriptRoot
Save-AzureRmContext -Path "$env:TEMP\profile.json" -Force -ErrorAction Stop

# Get catalog failover group
$catalogFailoverGroup = Get-AzureRmSqlDatabaseFailoverGroup `
                          -ResourceGroupName $wtpUser.ResourceGroupName `
                          -ServerName $originCatalogServerName `
                          -FailoverGroupName $catalogFailoverGroupName `
                          -ErrorAction Stop

# Failover recovery catalog database to origin (if applicable)
if (($catalogFailoverGroup.ReplicationState -eq 'CATCH_UP') -and ($catalogFailoverGroup.ReplicationRole -eq 'Secondary'))
{
  Write-Output "Failing over catalog database to origin ..."
  Switch-AzureRmSqlDatabaseFailoverGroup `
    -ResourceGroupName $wtpUser.ResourceGroupName `
    -ServerName $originCatalogServerName `
    -FailoverGroupName $catalogFailoverGroupName `
    >$null
}
elseif ($catalogFailoverGroup.ReplicationState -In 'PENDING', 'SEEDING')
{
  Write-Output "Catalog database in origin region is still being seeded with data from the recovery region. Try running the repatriation script again later."
  exit
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
    
# Enable traffic manager endpoint in origin, disable endpoint in recovery
Reset-TrafficManagerEndpoints 

$runningScripts = (Get-WmiObject -Class Win32_Process -Filter "Name='PowerShell.exe'") | Where-Object{$_.CommandLine -like "*Sync-TenantConfiguration*"}
foreach($script in $runningScripts)
{
  $script.Terminate() > $null
}
# Start background process to sync tenant server, pool, and database configuration info into the catalog 
Start-Process powershell.exe -ArgumentList "-NoExit &'$PSScriptRoot\Sync-TenantConfiguration.ps1'"

# Reconfigure servers and elastic pools in original region to match settings in the recovery region 
Write-Output "Reconfiguring tenant servers and elastic pools in original region to match recovery region ..."
$updateTenantResourcesJob = Start-Job -Name "ReconfigureTenantResources" -FilePath "$PSScriptRoot\RecoveryJobs\Update-TenantResourcesInOriginalRegion.ps1" -ArgumentList @($recoveryResourceGroupName)

# Mark any databases stuck in repatriating state as in error
$databaselist = Get-ExtendedDatabase -Catalog $catalog
foreach ($database in $databaselist)
{
  if ($database.RecoveryState -In 'replicating', 'repatriating')
  {
    $dbState = Update-TenantResourceRecoveryState -Catalog $catalog -UpdateAction "markError" -ServerName $database.ServerName -DatabaseName $database.DatabaseName
  }
}

# Wait to reconfigure servers and pools in origin region before proceeding
$reconfigureJobStatus = Wait-Job $updateTenantResourcesJob
if ($reconfigureJobStatus.State -eq "Failed")
{
  Receive-Job $updateTenantResourcesJob
  exit
}

# Start background job to replicate tenant databases that have been created in the recovery region
$replicateDbJob = Start-Job -Name "ReplicateDatabases" -FilePath "$PSScriptRoot\RecoveryJobs\Replicate-TenantDatabasesToOriginalRegion.ps1" -ArgumentList @($recoveryResourceGroupName)

# Start background job to failover tenant databases to the origin region
$failoverDbJob = Start-Job -Name "FailoverDatabases" -FilePath "$PSScriptRoot\RecoveryJobs\Failover-TenantDatabasesToOriginalRegion.ps1" -ArgumentList @($recoveryResourceGroupName)

# Start background job to mark tenants online in origin region when all required resources have been restored 
$tenantRecoveryJob = Start-Job -Name "TenantRecovery" -FilePath "$PSScriptRoot\RecoveryJobs\Enable-TenantsAfterRecoveryOperation.ps1" -ArgumentList @($recoveryResourceGroupName, "repatriation")

# Monitor state of all repatriation jobs 
while ($true)
{
  # Get state of all repatriation jobs. Stop repatriation if there is an error with any job
  $replicateDatabaseStatus = Receive-Job -Job $replicateDbJob -Keep -ErrorAction Stop
  $failoverDatabaseStatus = Receive-Job -Job $failoverDbJob -Keep -ErrorAction Stop
  $tenantRecoveryStatus = Receive-Job -Job $tenantRecoveryJob -Keep -ErrorAction Stop 

  # Initialize and format output for recovery jobs 
  $failoverDatabaseStatus = Format-JobOutput $failoverDatabaseStatus
  $tenantRecoveryStatus = Format-JobOutput $tenantRecoveryStatus
 
  # Output status of repatriation jobs to console
  Write-Output "Databases geo-replicated and failed-over to original region: $failoverDatabaseStatus"
 
  # Exit recovery if all tenants have been repatriated to origin 
  if (($replicateDbJob.State -eq "Completed") -and ($failoverDbJob.State -eq "Completed") -and ($tenantRecoveryJob.State -eq "Completed"))
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
Write-Output "'$($wtpUser.ResourceGroupName)' deployment repatriated into '$primaryLocation' region in $elapsedTime minutes."     

