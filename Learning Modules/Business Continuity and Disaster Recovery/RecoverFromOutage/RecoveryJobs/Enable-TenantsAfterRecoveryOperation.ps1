<#
.SYNOPSIS
  Brings tenants back online after required resources are available in a region

.DESCRIPTION
  This script is intended to be run as a background job in Wingtip SaaS app environment scripts.
  The script marks tenants as online as their relevant resources become available after a restore or failover.

.PARAMETER WingtipRecoveryResourceGroup
  Resource group that is used to contain recovered resources

.EXAMPLE
  [PS] C:\>.\Enable-TenantsAfterRecoveryOperation.ps1 -WingtipRecoveryResourceGroup "sampleRecoveryResourceGroup"
#>
[cmdletbinding()]
param (
    [parameter(Mandatory=$true)]
    [String] $WingtipRecoveryResourceGroup  
)

Import-Module "$using:scriptPath\..\..\Common\CatalogAndDatabaseManagement" -Force
Import-Module "$using:scriptPath\..\..\WtpConfig" -Force
Import-Module "$using:scriptPath\..\..\UserConfig" -Force

# Stop execution on error 
$ErrorActionPreference = "Stop"
  
# Login to Azure subscription
$credentialLoad = Import-AzureRmContext -Path "$env:TEMP\profile.json"
if (!$credentialLoad)
{
    Initialize-Subscription
}

# Get deployment configuration  
$wtpUser = Get-UserConfig
$config = Get-Configuration
$currentSubscriptionId = Get-SubscriptionId

# Get the active tenant catalog 
$tenantCatalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name

# Get the recovery region resource group
$recoveryResourceGroup = Get-AzureRmResourceGroup -Name $WingtipRecoveryResourceGroup

# Mark tenants online as their databases become available
while ($true)
{
  $tenantList = Get-ExtendedTenant -Catalog $tenantCatalog
  $tenantCount = $tenantList.Count
  $offlineTenants = $tenantList | Where-Object {($_.TenantStatus -ne 'Online')}   
  $onlineTenantCount = $tenantCount - ($offlineTenants.Count)

  # Exit if all tenants are online 
  if (!$offlineTenants)
  {
    # Output recovery progress 
    Write-Output "100% ($tenantCount of $tenantCount)"
    break
  }
  else
  {
    # Add compound database name to list of offline tenants 
    foreach ($tenant in $offlineTenants)
    {
      $tenant | Add-Member "CompoundDatabaseName" "$($tenant.ServerName)/$($tenant.DatabaseName)"
    }

    # Get list of offline tenant databases and their recovery status 
    $offlineTenantDatabases = @()
    $offlineTenantDatabases += Get-ExtendedDatabase -Catalog $tenantCatalog | Where-Object {"$($_.ServerName)/$($_.DatabaseName)" -In $offlineTenants.CompoundDatabaseName}
    $restoredDatabaseObjects = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers/databases"

    # Update tenant status based on the status of database 
    # Note: this job can be sped up by checking the status of tenant databases in multiple background jobs
    foreach ($tenantDatabase in $offlineTenantDatabases)
    {
      $tenantKey = Get-TenantKey $tenantDatabase.DatabaseName
      $tenantRecoveryState = $tenantObject.RecoveryState
      $tenantObject = $offlineTenants | Where-Object {$_.DatabaseName -eq $tenantDatabase.DatabaseName}
      $tenantAliasName = ($tenantObject.TenantAlias -split ".database.windows.net")[0]
      
      if ($tenantDatabase.RecoveryState -In 'restoring')
      {
        # Update tenant recovery status to 'RecoveringTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startRecovery" -TenantKey $tenantKey
      }
      elseif (($tenantDatabase.RecoveryState -In 'restored') -and ($tenantRecoveryState = 'RecoveringTenantData'))
      {
        # Update tenant recovery status to 'RecoveredTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endRecovery" -TenantKey $tenantKey

        # Update tenant recovery status to 'MarkingTenantOnlineInRecovery'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasFailoverToRecovery" -TenantKey $tenantKey

        # Take tenant offline
        Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey 
        
        # Get recovered tenant resources
        $restoredTenantDatabase = $restoredDatabaseObjects.Name -match "[\w-]+/$($tenantDatabase.DatabaseName)$"
        $restoredTenantServer = $restoredTenantDatabase.Split('/')[0] 
               
        # Update tenant alias to point to recovered database        
        Set-DnsAlias `
          -ResourceGroupName $WingtipRecoveryResourceGroup `
          -ServerName $restoredTenantServer `
          -ServerDNSAlias $tenantAliasName `
          -OldServerName $tenantDatabase.ServerName `
          -OldResourceGroupName $wtpUser.ResourceGroupName                
      }
      elseif (($tenantDatabase.RecoveryState -In 'restored') -and ($tenantRecoveryState = 'RecoveredTenantData'))
      {
        # Update tenant recovery status to 'MarkingTenantOnlineInRecovery'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasFailoverToRecovery" -TenantKey $tenantKey

        # Take tenant offline
        Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey 
        
        # Get recovered tenant resources
        $restoredTenantDatabase = $restoredDatabaseObjects.Name -match "[\w-]+/$($tenantDatabase.DatabaseName)$"
        $restoredTenantServer = $restoredTenantDatabase.Split('/')[0] 
               
        # Update tenant alias to point to recovered database        
        Set-DnsAlias `
          -ResourceGroupName $WingtipRecoveryResourceGroup `
          -ServerName $restoredTenantServer `
          -ServerDNSAlias $tenantAliasName `
          -OldServerName $tenantDatabase.ServerName `
          -OldResourceGroupName $wtpUser.ResourceGroupName
      }
      elseif (($tenantDatabase.RecoveryState -In 'restored') -and ($tenantRecoveryState = 'MarkingTenantOnlineInRecovery'))
      {
        $restoredTenantDatabase = $restoredDatabaseObjects.Name -match "[\w-]+/$($tenantDatabase.DatabaseName)$"
        $restoredTenantServer = $restoredTenantDatabase.Split('/')[0] 
               
        # Update tenant alias to point to recovered database if applicable
        $aliasInRecoveryRegion = Get-AzureRmSqlServerDNSAlias `
                                    -ResourceGroupName $WingtipRecoveryResourceGroup `
                                    -ServerName $restoredTenantServer `
                                    -ServerDNSAliasName $tenantAliasName `
                                    -ErrorAction SilentlyContinue `
                                    2>$null
        if (!$aliasInRecoveryRegion)
        {
          Set-DnsAlias `
            -ResourceGroupName $WingtipRecoveryResourceGroup `
            -ServerName $restoredTenantServer `
            -ServerDNSAlias $tenantAliasName `
            -OldServerName $tenantDatabase.ServerName `
            -OldResourceGroupName $wtpUser.ResourceGroupName
        }


        # Check if DNS change to tenant alias has propagated
        $activeTenantServer = Get-ServerNameFromAlias $tenantAliasName
        if ($activeTenantServer -eq $restoredTenantServer)
        {
          # Bring tenant online
          Set-TenantOnline -Catalog $tenantCatalog -TenantKey $tenantKey  
          $onlineTenantCount += 1

          # Update tenant recovery status to 'OnlineInRecovery'
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endAliasFailoverToRecovery" -TenantKey $tenantKey

        }
      }
      elseif ($tenantDatabase.RecoveryState -In 'resetting')
      {
        # Update tenant recovery status to 'ResettingTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startReset" -TenantKey $tenantKey
      }
      elseif ($tenantDatabase.RecoveryState -In 'complete') -and ($tenantRecoveryState = 'ResettingTenantData')
      {
        # Update tenant recovery status to 'ResetTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endReset" -TenantKey $tenantKey

        # Update tenant recovery status to 'MarkingTenantOnlineInOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasFailoverToOrigin" -TenantKey $tenantKey

        # Take tenant offline 
        Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey

        # Get tenant resources
        $restoredTenantDatabase = $restoredDatabaseObjects.Name -match "[\w-]+/$($tenantDatabase.DatabaseName)$"
        $restoredTenantServer = $restoredTenantDatabase.Split('/')[0] 
        $originTenantServer = ($restoredTenantServer -split $config.RecoverySuffix)[0]

        # Update tenant alias to point to origin database 
        Set-DnsAlias `
          -ResourceGroupName $wtpUser.ResourceGroupName `
          -ServerName $originTenantServer `
          -ServerDNSAlias $tenantAliasName `
          -OldServerName $restoredTenantServer `
          -OldResourceGroupName $WingtipRecoveryResourceGroup
      }
      elseif (($tenantDatabase.RecoveryState -In 'complete') -and ($tenantRecoveryState = 'ResetTenantData')
      {
        # Update tenant recovery status to 'MarkingTenantOnlineInOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasFailoverToOrigin" -TenantKey $tenantKey

        # Take tenant offline 
        Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey

        # Get tenant resources
        $restoredTenantDatabase = $restoredDatabaseObjects.Name -match "[\w-]+/$($tenantDatabase.DatabaseName)$"
        $restoredTenantServer = $restoredTenantDatabase.Split('/')[0] 
        $originTenantServer = ($restoredTenantServer -split $config.RecoverySuffix)[0]

        # Update tenant alias to point to origin database 
        Set-DnsAlias `
          -ResourceGroupName $wtpUser.ResourceGroupName `
          -ServerName $originTenantServer `
          -ServerDNSAlias $tenantAliasName `
          -OldServerName $restoredTenantServer `
          -OldResourceGroupName $WingtipRecoveryResourceGroup
      }
      elseif (($tenantDatabase.RecoveryState -In 'complete') -and ($tenantRecoveryState = 'MarkingTenantOnlineInOrigin'))
      {
        $restoredTenantDatabase = $restoredDatabaseObjects.Name -match "[\w-]+/$($tenantDatabase.DatabaseName)$"
        $restoredTenantServer = $restoredTenantDatabase.Split('/')[0]
        $originTenantServer = ($restoredTenantServer -split $config.RecoverySuffix)[0] 
               
        # Update tenant alias to point to original database if applicable
        $aliasInOriginalRegion = Get-AzureRmSqlServerDNSAlias `
                                    -ResourceGroupName $wtpUser.ResourceGroupName `
                                    -ServerName $originTenantServer `
                                    -ServerDNSAliasName $tenantAliasName `
                                    -ErrorAction SilentlyContinue `
                                    2>$null
        if (!$aliasInOriginalRegion)
        {
          Set-DnsAlias `
            -ResourceGroupName $wtpUser.ResourceGroupName `
            -ServerName $originTenantServer `
            -ServerDNSAlias $tenantAliasName `
            -OldServerName $tenantDatabase.ServerName `
            -OldResourceGroupName $WingtipRecoveryResourceGroup
        }

        # Check if DNS change to tenant alias has propagated
        $activeTenantServer = Get-ServerNameFromAlias $tenantAliasName
        if ($activeTenantServer -eq $originTenantServer)
        {
          # Bring tenant online
          Set-TenantOnline -Catalog $tenantCatalog -TenantKey $tenantKey 
          $onlineTenantCount += 1 

          # Update tenant recovery status to 'OnlineInOrigin'
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endAliasFailoverToOrigin" -TenantKey $tenantKey
        } 
      }
      elseif ($tenantDatabase.RecoveryState -In 'replicating')
      {
        # Update tenant recovery status to 'RepatriatingTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startRepatriation" -TenantKey $tenantKey
      }
      elseif ($tenantDatabase.RecoveryState -In 'replicated')
      {
        # Update tenant recovery status to 'RepatriatingTenantData' if applicable
        if ($tenantRecoveryState -ne 'RepatriatingTenantData')
        {
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startRepatriation" -TenantKey $tenantKey
        }
      }
      elseif ($tenantDatabase.RecoveryState -In 'repatriating')
      {
        # Update tenant recovery status to 'RepatriatingTenantData' if applicable 
        if ($tenantRecoveryState -ne 'RepatriatingTenantData')
        {
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startRepatriation" -TenantKey $tenantKey
        }
      }
      elseif (($tenantDatabase.RecoveryState -In 'complete') -and ($tenantRecoveryState = 'RepatriatingTenantData'))
      {
        # Update tenant recovery status to 'RepatriatedTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endRepatriation" -TenantKey $tenantKey

        # Update tenant recovery status to 'MarkingTenantOnlineInOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasFailoverToOrigin" -TenantKey $tenantKey

        # Take tenant offline 
        Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey

        # Get tenant resources
        $restoredTenantDatabase = $restoredDatabaseObjects.Name -match "[\w-]+/$($tenantDatabase.DatabaseName)$"
        $restoredTenantServer = $restoredTenantDatabase.Split('/')[0] 
        $originTenantServer = ($restoredTenantServer -split $config.RecoverySuffix)[0]

        # Update tenant alias to point to origin database 
        Set-DnsAlias `
          -ResourceGroupName $wtpUser.ResourceGroupName `
          -ServerName $originTenantServer `
          -ServerDNSAlias $tenantAliasName `
          -OldServerName $restoredTenantServer `
          -OldResourceGroupName $WingtipRecoveryResourceGroup
      }
      elseif (($tenantDatabase.RecoveryState -In 'complete') -and ($tenantRecoveryState = 'RepatriatedTenantData'))
      {
        # Update tenant recovery status to 'MarkingTenantOnlineInOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasFailoverToOrigin" -TenantKey $tenantKey

        # Take tenant offline 
        Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey

        # Get tenant resources
        $restoredTenantDatabase = $restoredDatabaseObjects.Name -match "[\w-]+/$($tenantDatabase.DatabaseName)$"
        $restoredTenantServer = $restoredTenantDatabase.Split('/')[0] 
        $originTenantServer = ($restoredTenantServer -split $config.RecoverySuffix)[0]

        # Update tenant alias to point to origin database 
        Set-DnsAlias `
          -ResourceGroupName $wtpUser.ResourceGroupName `
          -ServerName $originTenantServer `
          -ServerDNSAlias $tenantAliasName `
          -OldServerName $restoredTenantServer `
          -OldResourceGroupName $WingtipRecoveryResourceGroup
      }

      if (!$tenantState)
      {
        Write-Verbose "Tenant was in an invalid initial recovery state when recovery operation attempted: $tenantRecoveryState"
      }
    }

    # Output recovery progress 
    $TenantRecoveryPercentage = [math]::Round($onlineTenantCount/$tenantCount,2)
    $TenantRecoveryPercentage = $TenantRecoveryPercentage * 100
    Write-Output "$TenantRecoveryPercentage% ($onlineTenantCount of $tenantCount)"
  }      
}
