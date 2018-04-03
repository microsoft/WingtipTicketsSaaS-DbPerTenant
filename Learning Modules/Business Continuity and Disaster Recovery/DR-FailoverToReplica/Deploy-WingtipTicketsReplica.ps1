<#
.SYNOPSIS
  Creates a replica of the Wingtip Tickets application and databases in a recovery region 

.DESCRIPTION
  This script creates DR replicas of the apps and databases in a Wingtip Tickets deployment.
  SQL database georeplication is used to ensure data is synced and consistent with the original database instance. 

.PARAMETER RecoveryRegion
  The recovery region to deploy the Wingtip Tickets replicas to.
  If no option is selected, the paired Azure region will be selected

.PARAMETER StatusCheckTimeInterval
  This determines often the script will check on the status of background replication jobs. The script will wait the provided time in seconds before checking the status again.

.PARAMETER NoEcho
  This stops the output of the signed in user to prevent double echo of subscription details

.EXAMPLE
  [PS] C:\>.\Deploy-WingtipTicketsReplica
#>
[cmdletbinding()]
param (
    [parameter(Mandatory=$false)]
    [string] $RecoveryRegion,

    # NoEcho stops the output of the signed in user to prevent double echo  
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

# Stop execution on error 
$ErrorActionPreference = "Stop"

# Get deployment configuration  
$wtpUser = Get-UserConfig
$config = Get-Configuration

# Get Azure credentials
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

# Use input recovery location or get paired Azure region as recovery region (more info: https://docs.microsoft.com/azure/best-practices-availability-paired-regions)
$content = Get-Content "$PSScriptRoot\..\..\Utilities\AzurePairedRegions.txt" | Out-String
$regionPairs = Invoke-Expression $content

if ($RecoveryRegion -and ($regionPairs.ContainsValue($RecoveryRegion)))
{
    $recoveryLocation = $RecoveryRegion
}
else
{
  Write-Verbose "Did not receive valid recovery region as input. Using paired Azure region..."
  $primaryLocation = (Get-AzureRmResourceGroup -ResourceGroupName $wtpUser.ResourceGroupName).Location
  $recoveryLocation = $regionPairs.Item($primaryLocation)    
}

$startTime = Get-Date

# Get the active tenant catalog 
$catalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name

# Create recovery resource group if applicable 
$recoveryResourceGroupName = $wtpUser.ResourceGroupName + $config.RecoveryRoleSuffix
$recoveryResourceGroup = New-AzureRmResourceGroup -Name $recoveryResourceGroupName -Location $recoveryLocation -Force

# Initalize Azure context for background scripts  
$scriptPath= $PSScriptRoot
Save-AzureRmContext -Path "$env:TEMP\profile.json" -Force -ErrorAction Stop

# Deploy App replica into recovery region using ARM template
$appReplicaJob = Start-Job -Name "AppReplica" -FilePath "$PSScriptRoot\RecoveryJobs\Restore-WingtipSaaSAppToRecoveryRegion.ps1" -ArgumentList @($recoveryResourceGroupName)

# Deploy replicas of tenant servers and management servers into recovery region using ARM template
$serverReplicationJob = Start-Job -Name "ServerReplicas" -FilePath "$PSScriptRoot\RecoveryJobs\Replicate-ServersToRecoveryRegion.ps1" -ArgumentList @($recoveryResourceGroupName)

# Deploy replicas of tenant elastic pools into recovery region using ARM template
$poolReplicationJob = Start-Job -Name "PoolReplicas" -FilePath "$PSScriptRoot\RecoveryJobs\Replicate-TenantElasticPoolsToRecoveryRegion.ps1" -ArgumentList @($recoveryResourceGroupName)

# Deploy replicas of management databases into recovery region using ARM template
# Management databases are deployed into a failover group that can be failed over at once 
$managementServerReplicationJob = Start-Job -Name "ManagementDatabases" -FilePath "$PSScriptRoot\RecoveryJobs\Replicate-ManagementDatabasesToRecoveryRegion.ps1" -ArgumentList @($recoveryResourceGroupName)

# Deploy replicas of tenant databases using batch ARM template. 
# The template creates a SQL database failover group for each tenant
$databaseReplicationJob = Start-Job -Name "DatabaseReplicas" -FilePath "$PSScriptRoot\RecoveryJobs\Replicate-TenantDatabasesToRecoveryRegion.ps1" -ArgumentList @($recoveryResourceGroupName)

# Monitor status of background replication jobs. Exit when complete
while ($true)
{
  # Get state of all replication jobs. Stop replication if there is an error with any job
  $appReplicationStatus = Receive-Job -Job $appReplicaJob -Keep -ErrorAction Stop
  $serverReplicationStatus = Receive-Job -Job $serverReplicationJob -Keep -ErrorAction Stop
  $poolReplicationStatus = Receive-Job -Job $poolReplicationJob -Keep -ErrorAction Stop
  $managementServerReplicationStatus = Receive-Job -Job $managementServerReplicationJob -Keep -ErrorAction Stop
  $databaseReplicationStatus = Receive-Job -Job $databaseReplicationJob -Keep -ErrorAction Stop
  
  # Initialize and format output for recovery jobs 
  $appReplicationStatus = Format-JobOutput $appReplicationStatus
  $serverReplicationStatus = Format-JobOutput $serverReplicationStatus
  $poolReplicationStatus = Format-JobOutput $poolReplicationStatus
  $managementServerReplicationStatus = Format-JobOutput $managementServerReplicationStatus
  $databaseReplicationStatus = Format-JobOutput $databaseReplicationStatus
 
  # Output status of replication jobs to console
  [PSCustomObject] @{
    "Wingtip App" = $appReplicationStatus
    "Management & Tenant Servers" = $serverReplicationStatus
    "Tenant Pools" = $poolReplicationStatus
    "Catalog Database(s)" = $managementServerReplicationStatus    
    "Tenant Databases" = $databaseReplicationStatus  
  } | Format-List
  
  # Exit recovery if all tenant databases have been recovered 
  if (($databaseReplicationJob.State -eq "Completed") -and ($poolReplicationJob.State -eq "Completed") -and ($serverReplicationJob.State -eq "Completed") -and ($managementServerReplicationJob.State -eq "Completed"))
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
Write-Output "'$($wtpUser.ResourceGroupName)' deployment replicated into '$recoveryLocation' region in $elapsedTime minutes."
