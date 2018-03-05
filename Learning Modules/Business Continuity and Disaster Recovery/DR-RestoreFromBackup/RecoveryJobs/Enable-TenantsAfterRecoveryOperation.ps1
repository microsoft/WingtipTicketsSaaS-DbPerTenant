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

# Get the recovery region resource group
$recoveryResourceGroup = Get-AzureRmResourceGroup -Name $WingtipRecoveryResourceGroup

# Get the tenant catalog in the recovery region
$tenantCatalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name
while ($tenantCatalog.Database.ResourceGroupName -ne $recoveryResourceGroup.ResourceGroupName)
{
  Start-Sleep 10
  # Get the active tenant catalog
  $tenantCatalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name
}

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
    # Get list of offline tenant databases and their recovery status 
    $originTenantDatabases = @()
    $restoredTenantDatabases = @()
    $originTenantDatabases += Find-AzureRmResource -ResourceGroupNameEquals $wtpUser.ResourceGroupName -ResourceType "Microsoft.sql/servers/databases" -ResourceNameContains "tenants"
    $restoredTenantDatabases += Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers/databases" -ResourceNameContains "tenants"
    $databaseRecoveryStatuses = Get-ExtendedDatabase -Catalog $tenantCatalog | Where-Object {$_.ServerName -notmatch "$($config.RecoveryRoleSuffix)$"}

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
      $originTenantDatabase = $originTenantDatabases | Where-Object {$_.Name -match $tenant.DatabaseName}
      $restoredTenantDatabase = $restoredTenantDatabases | Where-Object {$_.Name -match $tenant.DatabaseName}
      $tenantDatabaseRecoveryStatus = $databaseRecoveryStatuses | Where-Object {$_.DatabaseName -eq $tenant.DatabaseName}
      
      if ($tenantDatabaseRecoveryStatus.RecoveryState -In ('restoring', 'failingOver'))
      {
        # Update tenant recovery status to 'RestoringTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startRecovery" -TenantKey $tenantKey
      }
      elseif (($tenantDatabaseRecoveryStatus.RecoveryState -In ('restored', 'failedOver')) -and ($tenantRecoveryState -eq 'RestoringTenantData'))
      {
        # Update tenant recovery status to 'RestoredTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endRecovery" -TenantKey $tenantKey

        # Take tenant offline if applicable
        if ($tenant.TenantStatus -ne "Offline")
        {
          Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey 
        }
        
        if ($restoredTenantDatabase)
        {
          # Get tenant resources
          $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0] 
          $originTenantServer = $originTenantDatabase.Name.Split('/')[0]
          
          # Update tenant recovery status to 'UpdatingTenantAliasToRecovery'
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasUpdateToRecovery" -TenantKey $tenantKey

          # Update tenant alias to point to recovered database        
          Set-DnsAlias `
            -ResourceGroupName $WingtipRecoveryResourceGroup `
            -ServerName $restoredTenantServer `
            -ServerDNSAlias $tenantAliasName `
            -OldServerName $originTenantServer `
            -OldResourceGroupName $wtpUser.ResourceGroupName
        }                
      }
      elseif (($tenantDatabaseRecoveryStatus.RecoveryState -In ('restored', 'failedOver')) -and ($tenantRecoveryState -eq 'RestoredTenantData'))
      {
        # Take tenant offline if applicable
        if ($tenant.TenantStatus -ne "Offline")
        {        
          Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey 
        }

        if ($restoredTenantDatabase)
        {
          # Get tenant resources
          $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0] 
          $originTenantServer = $originTenantDatabase.Name.Split('/')[0]

          # Update tenant recovery status to 'UpdatingTenantAliasToRecovery'
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasUpdateToRecovery" -TenantKey $tenantKey

          # Update tenant alias to point to recovered database if applicable
          $aliasInRecoveryRegion = Get-AzureRmSqlServerDnsAlias `
                                    -ResourceGroupName $WingtipRecoveryResourceGroup `
                                    -ServerName $restoredTenantServer `
                                    -DnsAliasName $tenantAliasName `
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
        }   
      }
      elseif (($tenantDatabaseRecoveryStatus.RecoveryState -In ('restored', 'failedOver')) -and ($tenantRecoveryState -eq 'UpdatingTenantAliasToRecovery'))
      {
        $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0]
        $originTenantServer = $originTenantDatabase.Name.Split('/')[0]  
               
        # Update tenant alias to point to recovered database if applicable
        $aliasInRecoveryRegion = Get-AzureRmSqlServerDnsAlias `
                                    -ResourceGroupName $WingtipRecoveryResourceGroup `
                                    -ServerName $restoredTenantServer `
                                    -DnsAliasName $tenantAliasName `
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
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endAliasUpdateToRecovery" -TenantKey $tenantKey

        }
      }
      elseif (($tenantDatabaseRecoveryStatus.RecoveryState -In ('restored', 'failedOver')) -and ($tenantRecoveryState -eq 'OnlineInRecovery'))
      {
        # Set tenant online if not already so 
        if ($tenant.TenantStatus -ne "Online")
        {
          Set-TenantOnline -Catalog $tenantCatalog -TenantKey $tenantKey
          $onlineTenantCount += 1         
        }
      }
      elseif (($restoredTenantDatabase) -and ($tenantDatabaseRecoveryStatus.RecoveryState -In 'resetting'))
      {
        # Update tenant recovery status to 'ResettingTenantToOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startReset" -TenantKey $tenantKey
      }
      elseif (($tenantDatabaseRecoveryStatus.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'ResettingTenantToOrigin'))
      {
        # Update tenant recovery status to 'ResetTenantToOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endReset" -TenantKey $tenantKey

        # Update tenant recovery status to 'UpdatingTenantAliasToOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasUpdateToOrigin" -TenantKey $tenantKey

        # Take tenant offline if applicable
        if ($tenant.TenantStatus -ne "Offline")
        {
          Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey
        }

        # Get tenant resources
        $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0]
        $originTenantServer = $originTenantDatabase.Name.Split('/')[0] 

        # Update tenant alias to point to origin database 
        Set-DnsAlias `
          -ResourceGroupName $wtpUser.ResourceGroupName `
          -ServerName $originTenantServer `
          -ServerDNSAlias $tenantAliasName `
          -OldServerName $restoredTenantServer `
          -OldResourceGroupName $WingtipRecoveryResourceGroup
      }
      elseif (($tenantDatabaseRecoveryStatus.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'ResetTenantToOrigin'))
      {
        # Update tenant recovery status to 'UpdatingTenantAliasToOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasUpdateToOrigin" -TenantKey $tenantKey

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
      elseif (($tenantDatabaseRecoveryStatus.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'UpdatingTenantAliasToOrigin'))
      {
        $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0]
        $originTenantServer = $originTenantDatabase.Name.Split('/')[0]  
               
        # Update tenant alias to point to original database if applicable
        $aliasInOriginalRegion = Get-AzureRmSqlServerDnsAlias `
                                    -ResourceGroupName $wtpUser.ResourceGroupName `
                                    -ServerName $originTenantServer `
                                    -DnsAliasName $tenantAliasName `
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
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endAliasUpdateToOrigin" -TenantKey $tenantKey
        } 
      }
      elseif (($restoredTenantDatabase) -and ($tenantDatabaseRecoveryStatus.RecoveryState -In 'replicating'))
      {
        # Update tenant recovery status to 'RepatriatingTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startRepatriation" -TenantKey $tenantKey
      }
      elseif (($restoredTenantDatabase) -and ($tenantDatabaseRecoveryStatus.RecoveryState -In 'replicated'))
      {
        # Update tenant recovery status to 'RepatriatingTenantData' if applicable
        if ($tenantRecoveryState -ne 'RepatriatingTenantData')
        {
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startRepatriation" -TenantKey $tenantKey
        }
      }
      elseif (($restoredTenantDatabase) -and ($tenantDatabaseRecoveryStatus.RecoveryState -In 'repatriating'))
      {
        # Update tenant recovery status to 'RepatriatingTenantData' if applicable 
        if ($tenantRecoveryState -ne 'RepatriatingTenantData')
        {
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startRepatriation" -TenantKey $tenantKey
        }
      }
      elseif (($tenantDatabaseRecoveryStatus.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'RepatriatingTenantData'))
      {
        # Update tenant recovery status to 'RepatriatedTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endRepatriation" -TenantKey $tenantKey

        # Update tenant recovery status to 'UpdatingTenantAliasToOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasUpdateToOrigin" -TenantKey $tenantKey

        # Take tenant offline if applicable
        if ($tenant.TenantStatus -ne "Offline")
        {
          Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey
        }

        # Get tenant resources
        $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0]
        $originTenantServer = $originTenantDatabase.Name.Split('/')[0] 

        # Update tenant alias to point to origin database 
        Set-DnsAlias `
          -ResourceGroupName $wtpUser.ResourceGroupName `
          -ServerName $originTenantServer `
          -ServerDNSAlias $tenantAliasName `
          -OldServerName $restoredTenantServer `
          -OldResourceGroupName $WingtipRecoveryResourceGroup
      }
      elseif (($tenantDatabaseRecoveryStatus.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'RepatriatedTenantData'))
      {
        # Update tenant recovery status to 'UpdatingTenantAliasToOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startAliasUpdateToOrigin" -TenantKey $tenantKey

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
      elseif (($tenantDatabaseRecoveryStatus.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'OnlineInOrigin'))
      {
        # Set tenant online if not already so 
        if ($tenant.TenantStatus -ne "Online")
        {
          Set-TenantOnline -Catalog $tenantCatalog -TenantKey $tenantKey         
        }
      }

      if (!$tenantState)
      {
        Write-Verbose "Tenant was in an invalid initial recovery state when recovery operation attempted: $tenantRecoveryState"
      }

       # Output recovery progress 
      $TenantRecoveryPercentage = [math]::Round($onlineTenantCount/$tenantCount,2)
      $TenantRecoveryPercentage = $TenantRecoveryPercentage * 100
      Write-Output "$TenantRecoveryPercentage% ($onlineTenantCount of $tenantCount)"
    }

    # Output recovery progress 
    $TenantRecoveryPercentage = [math]::Round($onlineTenantCount/$tenantCount,2)
    $TenantRecoveryPercentage = $TenantRecoveryPercentage * 100
    Write-Output "$TenantRecoveryPercentage% ($onlineTenantCount of $tenantCount)"
  }      
}