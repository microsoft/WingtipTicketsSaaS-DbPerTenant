<#
.SYNOPSIS
  Creates a new tenant server and elastic pool in the input resource group. 
  The script additionally geo-replicates the golden tenant database that is used to create new tenant databases

.DESCRIPTION
  This script is intended to be run as a background job in the Wingtip SaaS app recovery scripts.
  The script creates a server and elastic pool that will be used to host new tenant databases while recovery runs.
  The script also creates a georeplica of the golden tenant database that is used to create new tenant databases

.PARAMETER ResourceGroupName
  Resource group that will be used to contain new tenant resources

.PARAMETER ServerName
  Servername for new tenant server that will be created 


.EXAMPLE
  [PS] C:\>.\New-TenantResources.ps1 -ResourceGroupName "Sample-RecoveryGroup" -ServerName "Sample-tenant2"
#>
[cmdletbinding()]
param (
    [parameter(Position=0,Mandatory=$false)]
    [String] $ResourceGroupName,

    [parameter(Position=1,Mandatory=$false)]
    [String] $ServerName
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

$config = Get-Configuration
$wtpUser = Get-UserConfig
$currentSubscriptionId = Get-SubscriptionId

$sleepInterval = 10
$pastDeploymentWaitTime = 0
$deploymentName = "NewTenantProvisioning"

# Find any previous provisioning operation 
# This allows the script to be re-run if an error during deployment 
$pastDeployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $deploymentName -ErrorAction SilentlyContinue 2>$null

# Wait for past deployment to complete if it's still active 
while (($pastDeployment) -and ($pastDeployment.ProvisioningState -NotIn "Succeeded", "Failed", "Canceled"))
{
  # Wait for no more than 5 minutes (300 secs) for previous deployment to complete
  if ($pastDeploymentWaitTime -lt 300)
  {
      Write-Output "Waiting for previous deployment to complete ..."
      Start-Sleep $sleepInterval
      $pastDeploymentWaitTime += $sleepInterval
      $pastDeployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $deploymentName -ErrorAction SilentlyContinue 2>$null    
  }
  else
  {
      Stop-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $deploymentName -ErrorAction SilentlyContinue 1>$null 2>$null
      break
  }
  
}

# Output recovery progress 
if ($ReplicateGoldenTenantDatabase)
{
  Write-Output "0% (0 of 3)"
}
else
{
  Write-Output "0% (0 of 2)" 
}


# Create a tenant server with firewall rules, and an elastic pool for new tenants (idempotent)
# Note: In a production scenario you would additionally create logins and users that need to exist on the server(see: https://docs.microsoft.com/en-us/azure/sql-database/sql-database-disaster-recovery)
$existingGoldenTenantDatabase = Find-AzureRmResource -ResourceGroupNameEquals $ResourceGroupName -ResourceType "Microsoft.sql/servers/databases" -ResourceNameContains $config.GoldenTenantDatabaseName
if ($existingGoldenTenantDatabase)
{
  $deployment = New-AzureRmResourceGroupDeployment `
                    -Name $deploymentName `
                    -ResourceGroupName $ResourceGroupName `
                    -TemplateFile ("$using:scriptPath\RecoveryTemplates\" + $config.NewTenantResourcesProvisioningTemplate) `
                    -serverName $ServerName `
                    -ReplicateGoldenTenantDatabase "false" `
                    -ErrorAction Stop

  # Output recovery progress 
  Write-Output "100% (2 of 2)" 
}
else
{
  # Geo-replicate golden tenant database in addition to create a tenant server with firewall rules, and an elastic pool for new tenants (idempotent)
  $recoveryCatalogServerName = $config.CatalogServerNameStem + $wtpUser.Name + $config.RecoverySuffix
  $originCatalogServerName = $config.CatalogServerNameStem + $wtpUser.Name
  $baseTenantDatabaseId = "/subscriptions/$currentSubscriptionId/resourceGroups/$($wtpUser.ResourceGroupName)/providers/Microsoft.Sql/servers/$originCatalogServerName/recoverabledatabases/$($config.GoldenTenantDatabaseName)"

  $goldenTenantDatabaseConfig = @{
    CatalogServerName = "$recoveryCatalogServerName"
    DatabaseName = "$($config.GoldenTenantDatabaseName)"
    SourceDatabaseId = "$baseTenantDatabaseId"
    ServiceObjectiveName = "S1"
  }

  $deployment = New-AzureRmResourceGroupDeployment `
                    -Name $deploymentName `
                    -ResourceGroupName $ResourceGroupName `
                    -TemplateFile ("$using:scriptPath\RecoveryTemplates\" + $config.NewTenantResourcesProvisioningTemplate) `
                    -serverName $ServerName `
                    -ReplicateGoldenTenantDatabase "true" `
                    -GoldenTenantDatabaseConfiguration $goldenTenantDatabaseConfig `
                    -ErrorAction Stop

  # Output recovery progress
  Write-Output "100% (3 of 3)"
}
