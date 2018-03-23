<#
.SYNOPSIS
  Deploys an instance of the Wingtip web application with a traffic manager endpoint to a recovery region 

.DESCRIPTION
  This script is intended to be run as a background job in the 'Restore-IntoSecondaryRegion' script that recovers the Wingtip SaaS app environment (apps, databases, servers e.t.c) into a recovery region.
  The script creates a web app, and a traffic manager endpoint that will be used in the recovery process.

.PARAMETER WingtipRecoveryResourceGroup
  Resource group that will be used to contain recovered resources

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
$recoveryLocation = (Get-AzureRmResourceGroup -ResourceGroupName $WingtipRecoveryResourceGroup).Location

# Get Wingtip web app if it exists
$recoveryWebAppName = $config.EventsAppNameStem + $recoveryLocation + '-' + $wtpUser.Name
$wingtipRecoveryApp = Find-AzureRmResource `
                        -ResourceType "Microsoft.Web/sites" `
                        -ResourceGroupNameEquals $WingtipRecoveryResourceGroup `
                        -ResourceNameEquals $recoveryWebAppName

if ($wingtipRecoveryApp)
{
    Write-Output "Done"
}
else
{
    Write-Output "Deploying ..."
    $templatePath = "$using:scriptPath\RecoveryTemplates\" + $config.WebApplicationRecoveryTemplate
    $catalogRecoveryServerName = $config.CatalogServerNameStem + $wtpUser.Name + $config.RecoveryRoleSuffix
    $tenantsRecoveryServerName = $config.TenantServerNameStem + $wtpUser.Name + $config.RecoveryRoleSuffix
    $deployment = New-AzureRmResourceGroupDeployment `
                    -Name $recoveryWebAppName `
                    -ResourceGroupName $WingtipRecoveryResourceGroup `
                    -TemplateFile $templatePath `
                    -WtpUser $wtpUser.Name `
                    -WtpOriginResourceGroup $wtpUser.ResourceGroupName `
                    -RecoverySuffix $config.RecoveryRoleSuffix `
                    -CatalogRecoveryServer $catalogRecoveryServerName `
                    -TenantsRecoveryServer $tenantsRecoveryServerName `
                    -ErrorAction Stop

    Write-Output "Done"                    
}
