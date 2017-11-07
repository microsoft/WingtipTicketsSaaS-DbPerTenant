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

# Import-Module "$PSScriptRoot\..\..\..\Common\CatalogAndDatabaseManagement" -Force
# Import-Module "$PSScriptRoot\..\..\..\WtpConfig" -Force
# Import-Module "$PSScriptRoot\..\..\..\UserConfig" -Force

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
    $originTenantDatabases = @()
    $originTenantDatabases += Get-ExtendedDatabase -Catalog $tenantCatalog | Where-Object {($_.ServerName -NotMatch "$($config.RecoverySuffix)$")}
    $restoredTenantDatabases = Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers/databases"

    # Output recovery progress 
    $TenantRecoveryPercentage = [math]::Round($onlineTenantCount/$tenantCount,2)
    $TenantRecoveryPercentage = $TenantRecoveryPercentage * 100
    Write-Output "$TenantRecoveryPercentage% ($onlineTenantCount of $tenantCount)"

    # Update tenant status based on the status of database 
    # Note: this job can be sped up by checking the status of tenant databases in multiple background jobs
    foreach ($tenant in $offlineTenants)
    {
      $tenantKey = Get-TenantKey $tenant.TenantName
      $tenantRecoveryState = $tenant.TenantRecoveryState     
      $tenantAliasName = ($tenant.TenantAlias -split ".database.windows.net")[0]
      $activeTenantDatabase = $tenant.CompoundDatabaseName
      $originTenantDatabase = $originTenantDatabases | Where-Object {$_.DatabaseName -eq $tenant.DatabaseName}
      $restoredTenantDatabase = $restoredTenantDatabases | Where-Object {$_.Name -match $tenant.DatabaseName}
      
      if ($originTenantDatabase.RecoveryState -In 'restoring')
      {
        # Update tenant recovery status to 'RecoveringTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startRecovery" -TenantKey $tenantKey
      }
      elseif (($originTenantDatabase.RecoveryState -In 'restored') -and ($tenantRecoveryState -eq 'RecoveringTenantData'))
      {
        # Update tenant recovery status to 'RecoveredTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endRecovery" -TenantKey $tenantKey

        # Update tenant recovery status to 'MarkingTenantOnlineInRecovery'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasFailoverToRecovery" -TenantKey $tenantKey

        # Take tenant offline if applicable
        if ($tenant.TenantStatus -ne "Offline")
        {
          Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey 
        }
        
        # Get tenant resources
        $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0] 
        $originTenantServer = $originTenantDatabase.ServerName
               
        # Update tenant alias to point to recovered database        
        Set-DnsAlias `
          -ResourceGroupName $WingtipRecoveryResourceGroup `
          -ServerName $restoredTenantServer `
          -ServerDNSAlias $tenantAliasName `
          -OldServerName $originTenantServer `
          -OldResourceGroupName $wtpUser.ResourceGroupName                
      }
      elseif (($originTenantDatabase.RecoveryState -In 'restored') -and ($tenantRecoveryState -eq 'RecoveredTenantData'))
      {
        # Update tenant recovery status to 'MarkingTenantOnlineInRecovery'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasFailoverToRecovery" -TenantKey $tenantKey

        # Take tenant offline if applicable
        if ($tenant.TenantStatus -ne "Offline")
        {        
          Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey 
        }
        
        # Get tenant resources
        $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0] 
        $originTenantServer = $originTenantDatabase.ServerName
               
        # Update tenant alias to point to recovered database        
        Set-DnsAlias `
          -ResourceGroupName $WingtipRecoveryResourceGroup `
          -ServerName $restoredTenantServer `
          -ServerDNSAlias $tenantAliasName `
          -OldServerName $originTenantServer `
          -OldResourceGroupName $wtpUser.ResourceGroupName
      }
      elseif (($originTenantDatabase.RecoveryState -In 'restored') -and ($tenantRecoveryState -eq 'MarkingTenantOnlineInRecovery'))
      {
        $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0]
        $originTenantServer = $originTenantDatabase.ServerName  
               
        # Update tenant alias to point to recovered database if applicable
        $aliasInRecoveryRegion = Get-AzureRmSqlServerDNSAlias `
                                    -ResourceGroupName $WingtipRecoveryResourceGroup `
                                    -ServerName $restoredTenantServer `
                                    -ServerDNSAliasName $tenantAliasName `
                                    -ErrorAction SilentlyContinue
        if (!$aliasInRecoveryRegion)
        {
          Set-DnsAlias `
            -ResourceGroupName $WingtipRecoveryResourceGroup `
            -ServerName $restoredTenantServer `
            -ServerDNSAlias $tenantAliasName `
            -OldServerName $originTenantServer `
            -OldResourceGroupName $wtpUser.ResourceGroupName
        }

        # Check if DNS change to tenant alias has propagated
        $activeTenantServer = Get-ServerNameFromAlias "$tenantAliasName.database.windows.net"
        if ($activeTenantServer -eq $restoredTenantServer)
        {
          # Bring tenant online
          Set-TenantOnline -Catalog $tenantCatalog -TenantKey $tenantKey  
          $onlineTenantCount += 1

          # Update tenant recovery status to 'OnlineInRecovery'
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endAliasFailoverToRecovery" -TenantKey $tenantKey

        }
      }
      elseif (($restoredTenantDatabase) -and ($restoredTenantDatabase.RecoveryState -In 'resetting'))
      {
        # Update tenant recovery status to 'ResettingTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startReset" -TenantKey $tenantKey
      }
      elseif (($originTenantDatabase.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'ResettingTenantData'))
      {
        # Update tenant recovery status to 'ResetTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endReset" -TenantKey $tenantKey

        # Update tenant recovery status to 'MarkingTenantOnlineInOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasFailoverToOrigin" -TenantKey $tenantKey

        # Take tenant offline if applicable
        if ($tenant.TenantStatus -ne "Offline")
        {
          Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey
        }

        # Get tenant resources
        $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0]
        $originTenantServer = $originTenantDatabase.ServerName 

        # Update tenant alias to point to origin database 
        Set-DnsAlias `
          -ResourceGroupName $wtpUser.ResourceGroupName `
          -ServerName $originTenantServer `
          -ServerDNSAlias $tenantAliasName `
          -OldServerName $restoredTenantServer `
          -OldResourceGroupName $WingtipRecoveryResourceGroup
      }
      elseif (($originTenantDatabase.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'ResetTenantData'))
      {
        # Update tenant recovery status to 'MarkingTenantOnlineInOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasFailoverToOrigin" -TenantKey $tenantKey

        # Take tenant offline if applicable
        if ($tenant.TenantStatus -ne "Offline")
        {
          Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey
        }

        # Get tenant resources
        $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0]
        $originTenantServer = $originTenantDatabase.ServerName 

        # Update tenant alias to point to origin database 
        Set-DnsAlias `
          -ResourceGroupName $wtpUser.ResourceGroupName `
          -ServerName $originTenantServer `
          -ServerDNSAlias $tenantAliasName `
          -OldServerName $restoredTenantServer `
          -OldResourceGroupName $WingtipRecoveryResourceGroup
      }
      elseif (($originTenantDatabase.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'MarkingTenantOnlineInOrigin'))
      {
        $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0]
        $originTenantServer = $originTenantDatabase.ServerName  
               
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
            -OldServerName $restoredTenantServer `
            -OldResourceGroupName $WingtipRecoveryResourceGroup
        }

        # Check if DNS change to tenant alias has propagated
        $activeTenantServer = Get-ServerNameFromAlias "$tenantAliasName.database.windows.net"
        if ($activeTenantServer -eq $originTenantServer)
        {
          # Bring tenant online
          Set-TenantOnline -Catalog $tenantCatalog -TenantKey $tenantKey 
          $onlineTenantCount += 1 

          # Update tenant recovery status to 'OnlineInOrigin'
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endAliasFailoverToOrigin" -TenantKey $tenantKey
        } 
      }
      elseif (($restoredTenantDatabase) -and ($restoredTenantDatabase.RecoveryState -In 'replicating'))
      {
        # Update tenant recovery status to 'RepatriatingTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startRepatriation" -TenantKey $tenantKey
      }
      elseif (($restoredTenantDatabase) -and ($restoredTenantDatabase.RecoveryState -In 'replicated'))
      {
        # Update tenant recovery status to 'RepatriatingTenantData' if applicable
        if ($tenantRecoveryState -ne 'RepatriatingTenantData')
        {
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startRepatriation" -TenantKey $tenantKey
        }
      }
      elseif (($restoredTenantDatabase) -and ($restoredTenantDatabase.RecoveryState -In 'repatriating'))
      {
        # Update tenant recovery status to 'RepatriatingTenantData' if applicable 
        if ($tenantRecoveryState -ne 'RepatriatingTenantData')
        {
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startRepatriation" -TenantKey $tenantKey
        }
      }
      elseif (($originTenantDatabase.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'RepatriatingTenantData'))
      {
        # Update tenant recovery status to 'RepatriatedTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endRepatriation" -TenantKey $tenantKey

        # Update tenant recovery status to 'MarkingTenantOnlineInOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasFailoverToOrigin" -TenantKey $tenantKey

        # Take tenant offline if applicable
        if ($tenant.TenantStatus -ne "Offline")
        {
          Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey
        }

        # Get tenant resources
        $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0]
        $originTenantServer = $originTenantDatabase.ServerName 

        # Update tenant alias to point to origin database 
        Set-DnsAlias `
          -ResourceGroupName $wtpUser.ResourceGroupName `
          -ServerName $originTenantServer `
          -ServerDNSAlias $tenantAliasName `
          -OldServerName $restoredTenantServer `
          -OldResourceGroupName $WingtipRecoveryResourceGroup
      }
      elseif (($originTenantDatabase.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'RepatriatedTenantData'))
      {
        # Update tenant recovery status to 'MarkingTenantOnlineInOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasFailoverToOrigin" -TenantKey $tenantKey

        # Take tenant offline if applicable
        if ($tenant.TenantStatus)
        {
          Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey
        }

        # Get tenant resources
        $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0]
        $originTenantServer = $originTenantDatabase.ServerName 

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
