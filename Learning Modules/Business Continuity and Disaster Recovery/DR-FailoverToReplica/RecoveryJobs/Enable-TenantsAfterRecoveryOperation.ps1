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
    [String] $WingtipRecoveryResourceGroup,

    [parameter(Mandatory=$false)]
    [validateset('restore', 'repatriation')]
    [string]$RecoveryOperation ="restore"
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


# Get the active tenant catalog
$tenantCatalog = Get-Catalog -ResourceGroupName $WingtipRecoveryResourceGroup -WtpUser $wtpUser.Name

# Mark tenants online as their databases become available
while ($true)
{
  $tenantList = Get-ExtendedTenant -Catalog $tenantCatalog
  $tenantCount = (Get-Tenants -Catalog $tenantCatalog).Count
  $offlineTenants = @($tenantList).Where({(($_.TenantStatus -ne 'Online') -or ($_.TenantRecoveryState -In 'n/a', 'OnlineInOrigin'))})
  $tenantsInRecovery = @($tenantList).Where({$_.TenantRecoveryState -ne 'OnlineInOrigin'})
  $onlineTenantCount = $tenantCount - ($offlineTenants.Count)
  $repatriatedTenantCount = $tenantCount - ($tenantsInRecovery.Count)

  # Exit if all tenants are online after recovery operation
  if (!$offlineTenants -and ($RecoveryOperation -eq 'restore'))
  {
    # Output recovery progress 
    Write-Output "100% ($onlineTenantCount of $tenantCount)"
    break
  }
  # Exit if all tenants are online in origin after repatriation operation
  elseif (!$tenantsInRecovery -and ($RecoveryOperation -eq 'repatriation'))
  {
    # Output recovery progress 
    Write-Output "100% ($repatriatedTenantCount of $tenantCount)"
    break
  }
  else
  {
    # Get list of offline tenant databases and their recovery status 
    $originTenantDatabases = @()
    $restoredTenantDatabases = @()
    $originTenantDatabases += Find-AzureRmResource -ResourceGroupNameEquals $wtpUser.ResourceGroupName -ResourceType "Microsoft.sql/servers/databases" -ResourceNameContains "tenants"
    $restoredTenantDatabases += Find-AzureRmResource -ResourceGroupNameEquals $WingtipRecoveryResourceGroup -ResourceType "Microsoft.sql/servers/databases" -ResourceNameContains "tenants"
    $databaseRecoveryStatuses = Get-ExtendedDatabase -Catalog $tenantCatalog

    # Output recovery progress 
    if ($RecoveryOperation -eq 'restore')
    {
      $TenantRecoveryPercentage = [math]::Round($onlineTenantCount/$tenantCount,2)
      $TenantRecoveryPercentage = $TenantRecoveryPercentage * 100
      Write-Output "$TenantRecoveryPercentage% ($onlineTenantCount of $tenantCount)"
    }
    elseif ($RecoveryOperation -eq 'repatriation')
    {
      $TenantRecoveryPercentage = [math]::Round($repatriatedTenantCount/$tenantCount,2)
      $TenantRecoveryPercentage = $TenantRecoveryPercentage * 100
      Write-Output "$TenantRecoveryPercentage% ($repatriatedTenantCount of $tenantCount)"
    }

    # Update tenant status based on the status of database 
    # Note: this job can be sped up by checking the status of tenant databases in multiple background jobs
    if ($RecoveryOperation -eq 'repatriation')
    {
      $relevantTenantList = $tenantsInRecovery
    }
    else
    {
      $relevantTenantList = $offlineTenants
    }

    foreach ($tenant in $relevantTenantList)
    {
      $tenantKey = Get-TenantKey $tenant.TenantName
      $tenantRecoveryState = $tenant.TenantRecoveryState     
      $originTenantDatabase = $originTenantDatabases | Where-Object {$_.Name -match $tenant.DatabaseName}
      $restoredTenantDatabase = $restoredTenantDatabases | Where-Object {$_.Name -match $tenant.DatabaseName}
      $originDatabaseRecoveryStatus = $databaseRecoveryStatuses | Where-Object{(($_.DatabaseName -eq $tenant.DatabaseName) -and ($_.ServerName -notmatch "$($config.RecoveryRoleSuffix)$"))}
      $restoredDatabaseRecoveryStatus = $databaseRecoveryStatuses | Where-Object{(($_.DatabaseName -eq $tenant.DatabaseName) -and ($_.ServerName -match "$($config.RecoveryRoleSuffix)$"))}
      
      if ($originDatabaseRecoveryStatus.RecoveryState -In ('restoring', 'failingOver'))
      {
        # Update tenant recovery status to 'RestoringTenantData' (if applicable)
        if ($tenantRecoveryState -ne 'RestoringTenantData')
        {
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startRecovery" -TenantKey $tenantKey
        }
      }
      elseif (($originDatabaseRecoveryStatus.RecoveryState -In ('restored', 'failedOver')) -and ($tenantRecoveryState -In 'RestoringTenantData', 'n/a'))
      {
        # Update tenant recovery status to 'RestoredTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endRecovery" -TenantKey $tenantKey

        # Take tenant offline if applicable
        if ($tenant.TenantStatus -ne "Offline")
        {
          Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey 
        }  
      }
      elseif ($restoredTenantDatabase -and !$originTenantDatabase)
      {
        # Mark tenants that are created in the recovery region as 'OnlineInRecovery'
        if ($tenantRecoveryState -ne 'OnlineInRecovery')
        {
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endRecovery" -TenantKey $tenantKey
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startShardUpdateToRecovery" -TenantKey $tenantKey
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endShardUpdateToRecovery" -TenantKey $tenantKey
        }
      }
      elseif (($originDatabaseRecoveryStatus.RecoveryState -In ('restored', 'failedOver')) -and ($tenantRecoveryState -eq 'RestoredTenantData'))
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

          # Update tenant recovery status to 'UpdatingTenantShardToRecovery'
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startShardUpdateToRecovery" -TenantKey $tenantKey

          # Update tenant shard to point to recovered database
          $updateComplete = Update-TenantShardInfo `
                            -Catalog $tenantCatalog `
                            -TenantName $tenant.TenantName `
                            -FullyQualifiedTenantServerName "$restoredTenantServer.database.windows.net" `
                            -TenantDatabaseName $tenant.DatabaseName

          if ($updateComplete)
          {
            # Mark tenant online in catalog
            Set-TenantOnline -Catalog $tenantCatalog -TenantKey $tenantKey

            # Check if recovery database entry exists in catalog for tenant
            $recoveryDatabaseEntry = Get-ExtendedDatabase -Catalog $tenantCatalog -ServerName $restoredTenantServer -DatabaseName $tenant.DatabaseName
            if (!$recoveryDatabaseEntry)
            {
              # Add recovery database entry in catalog
              $recoveryDatabase = Get-AzureRmSqlDatabase -ResourceGroupName $WingtipRecoveryResourceGroup -ServerName $restoredTenantServer -DatabaseName $tenant.DatabaseName
              Set-ExtendedDatabase -Catalog $tenantCatalog -Database $recoveryDatabase
            }       
            Set-TenantDatabaseRecoveryChecksum -Catalog $tenantCatalog -ServerName $restoredTenantServer -DatabaseName $tenant.DatabaseName
            $onlineTenantCount +=1
            
            # Update tenant recovery status to 'OnlineInRecovery'
            $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endShardUpdateToRecovery" -TenantKey $tenantKey
          }
        }   
      }
      elseif (($originDatabaseRecoveryStatus.RecoveryState -In ('restored', 'failedOver')) -and ($tenantRecoveryState -eq 'UpdatingTenantShardToRecovery'))
      {
        $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0]
        $originTenantServer = $originTenantDatabase.Name.Split('/')[0]  
               
        # Update tenant shard to point to recovered database
        $updateComplete = Update-TenantShardInfo `
                            -Catalog $tenantCatalog `
                            -TenantName $tenant.TenantName `
                            -FullyQualifiedTenantServerName "$restoredTenantServer.database.windows.net" `
                            -TenantDatabaseName $tenant.DatabaseName

        if ($updateComplete)
        {
          # Mark tenant online in catalog
          Set-TenantOnline -Catalog $tenantCatalog -TenantKey $tenantKey

          # Check if recovery database entry exists in catalog for tenant
          $recoveryDatabaseEntry = Get-ExtendedDatabase -Catalog $tenantCatalog -ServerName $restoredTenantServer -DatabaseName $tenant.DatabaseName
          if (!$recoveryDatabaseEntry)
          {
            # Add recovery database entry in catalog
            $recoveryDatabase = Get-AzureRmSqlDatabase -ResourceGroupName $WingtipRecoveryResourceGroup -ServerName $restoredTenantServer -DatabaseName $tenant.DatabaseName
            Set-ExtendedDatabase -Catalog $tenantCatalog -Database $recoveryDatabase
          }
          Set-TenantDatabaseRecoveryChecksum -Catalog $tenantCatalog -ServerName $restoredTenantServer -DatabaseName $tenant.DatabaseName
          $onlineTenantCount +=1

          # Update tenant recovery status to 'OnlineInRecovery'
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endShardUpdateToRecovery" -TenantKey $tenantKey
        }     
      }
      elseif (($originDatabaseRecoveryStatus.RecoveryState -In ('restored', 'failedOver')) -and ($tenantRecoveryState -eq 'OnlineInRecovery'))
      {
        # Set tenant online if not already so 
        if ($tenant.TenantStatus -ne "Online")
        {
          Set-TenantOnline -Catalog $tenantCatalog -TenantKey $tenantKey

          # Check if recovery database entry exists in catalog for tenant
          $recoveryDatabaseEntry = Get-ExtendedDatabase -Catalog $tenantCatalog -ServerName $restoredTenantServer -DatabaseName $tenant.DatabaseName
          if (!$recoveryDatabaseEntry)
          {
            # Add recovery database entry in catalog
            $recoveryDatabase = Get-AzureRmSqlDatabase -ResourceGroupName $WingtipRecoveryResourceGroup -ServerName $restoredTenantServer -DatabaseName $tenant.DatabaseName
            Set-ExtendedDatabase -Catalog $tenantCatalog -Database $recoveryDatabase
          }
          Set-TenantDatabaseRecoveryChecksum -Catalog $tenantCatalog -ServerName $restoredTenantServer -DatabaseName $tenant.DatabaseName
          $onlineTenantCount += 1         
        }
      }
      elseif (($restoredTenantDatabase) -and ($restoredDatabaseRecoveryStatus.RecoveryState -In 'resetting'))
      {
        # Update tenant recovery status to 'ResettingTenantToOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startReset" -TenantKey $tenantKey
      }
      elseif (($originDatabaseRecoveryStatus.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'ResettingTenantToOrigin'))
      {
        if ($tenant.TenantStatus -ne 'Online')
        {
          Set-TenantOnline -Catalog $tenantCatalog -TenantKey $tenantKey
          $onlineTenantCount +=1
        }

        # Update tenant recovery status to 'OnlineInOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endReset" -TenantKey $tenantKey                
      }
      elseif (($originDatabaseRecoveryStatus.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'OnlineInOrigin'))
      {
        # Set tenant online if not already so 
        if ($tenant.TenantStatus -ne "Online")
        {
          Set-TenantOnline -Catalog $tenantCatalog -TenantKey $tenantKey
          $onlineTenantCount += 1         
        }
      }     
      elseif (($restoredTenantDatabase) -and ($restoredDatabaseRecoveryStatus.RecoveryState -In 'replicating', 'replicated', 'repatriating'))
      {
        # Update tenant recovery status to 'RepatriatingTenantData' if applicable 
        if ($tenantRecoveryState -ne 'RepatriatingTenantData')
        {
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startRepatriation" -TenantKey $tenantKey
        }
      }           
      elseif (($restoredDatabaseRecoveryStatus.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'RepatriatingTenantData'))
      {
        # Update tenant recovery status to 'RepatriatedTenantData'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endRepatriation" -TenantKey $tenantKey

        # Update tenant recovery status to 'UpdatingTenantShardToOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startShardUpdateToOrigin" -TenantKey $tenantKey

        # Take tenant offline if applicable
        if ($tenant.TenantStatus -ne "Offline")
        {
          Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey -ErrorAction SilentlyContinue
        }

        # Get tenant resources
        $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0]
        $originTenantServer = $originTenantDatabase.Name.Split('/')[0] 

        # Update tenant shard to point to origin database
        $updateComplete = Update-TenantShardInfo `
                            -Catalog $tenantCatalog `
                            -TenantName $tenant.TenantName `
                            -FullyQualifiedTenantServerName "$originTenantServer.database.windows.net" `
                            -TenantDatabaseName $tenant.DatabaseName

        if ($updateComplete)
        {
          # Mark tenant online in catalog
          Set-TenantOnline -Catalog $tenantCatalog -TenantKey $tenantKey
          $onlineTenantCount +=1

          # Update tenant recovery status to 'OnlineInOrigin'
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endShardUpdateToOrigin" -TenantKey $tenantKey
        }          
      }
      elseif (($restoredDatabaseRecoveryStatus.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'RepatriatedTenantData'))
      {
        # Update tenant recovery status to 'UpdatingTenantShardToOrigin'
        $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startShardUpdateToOrigin" -TenantKey $tenantKey

        # Take tenant offline if applicable
        if ($tenant.TenantStatus -ne "Offline")
        {
          Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey -ErrorAction SilentlyContinue
        }

        # Update tenant shard to point to recovered database
        $updateComplete = Update-TenantShardInfo `
                            -Catalog $tenantCatalog `
                            -TenantName $tenant.TenantName `
                            -FullyQualifiedTenantServerName "$originTenantServer.database.windows.net" `
                            -TenantDatabaseName $tenant.DatabaseName

        if ($updateComplete)
        {
          # Mark tenant online in catalog
          Set-TenantOnline -Catalog $tenantCatalog -TenantKey $tenantKey
          $onlineTenantCount +=1

          # Update tenant recovery status to 'OnlineInOrigin'
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endShardUpdateToOrigin" -TenantKey $tenantKey
        }  
      }
      elseif (($restoredDatabaseRecoveryStatus.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'OnlineInRecovery'))
      {
        # Update tenant recovery status to 'RepatriatingTenantData' if applicable 
        if ($tenantRecoveryState -ne 'RepatriatingTenantData')
        {
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "startRepatriation" -TenantKey $tenantKey
        }
      }
      elseif (($restoredDatabaseRecoveryStatus.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'UpdatingTenantShardToOrigin'))
      {
        $restoredTenantServer = $restoredTenantDatabase.Name.Split('/')[0]
        $originTenantServer = $originTenantDatabase.Name.Split('/')[0]  
               
        # Take tenant offline if applicable
        if ($tenant.TenantStatus -ne "Offline")
        {
          Set-TenantOffline -Catalog $tenantCatalog -TenantKey $tenantKey -ErrorAction SilentlyContinue
        }

        # Update tenant shard to point to origin database
        $updateComplete = Update-TenantShardInfo `
                            -Catalog $tenantCatalog `
                            -TenantName $tenant.TenantName `
                            -FullyQualifiedTenantServerName "$originTenantServer.database.windows.net" `
                            -TenantDatabaseName $tenant.DatabaseName

        if ($updateComplete)
        {
          # Mark tenant online in catalog
          Set-TenantOnline -Catalog $tenantCatalog -TenantKey $tenantKey
          $onlineTenantCount +=1

          # Update tenant recovery status to 'OnlineInOrigin'
          $tenantState = Update-TenantRecoveryState -Catalog $tenantCatalog -UpdateAction "endShardUpdateToOrigin" -TenantKey $tenantKey
        }  
      }
      elseif (($restoredDatabaseRecoveryStatus.RecoveryState -In 'complete') -and ($tenantRecoveryState -eq 'OnlineInOrigin'))
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
      if ($RecoveryOperation -eq 'restore')
      {
        $TenantRecoveryPercentage = [math]::Round($onlineTenantCount/$tenantCount,2)
        $TenantRecoveryPercentage = $TenantRecoveryPercentage * 100
        Write-Output "$TenantRecoveryPercentage% ($onlineTenantCount of $tenantCount)"
      }
      elseif ($RecoveryOperation -eq 'repatriation')
      {
        $TenantRecoveryPercentage = [math]::Round($repatriatedTenantCount/$tenantCount,2)
        $TenantRecoveryPercentage = $TenantRecoveryPercentage * 100
        Write-Output "$TenantRecoveryPercentage% ($repatriatedTenantCount of $tenantCount)"
      }
    }

    # Output recovery progress 
    if ($RecoveryOperation -eq 'restore')
    {
      $TenantRecoveryPercentage = [math]::Round($onlineTenantCount/$tenantCount,2)
      $TenantRecoveryPercentage = $TenantRecoveryPercentage * 100
      Write-Output "$TenantRecoveryPercentage% ($onlineTenantCount of $tenantCount)"
    }
    elseif ($RecoveryOperation -eq 'repatriation')
    {
      $TenantRecoveryPercentage = [math]::Round($repatriatedTenantCount/$tenantCount,2)
      $TenantRecoveryPercentage = $TenantRecoveryPercentage * 100
      Write-Output "$TenantRecoveryPercentage% ($repatriatedTenantCount of $tenantCount)"
    }
  }      
}