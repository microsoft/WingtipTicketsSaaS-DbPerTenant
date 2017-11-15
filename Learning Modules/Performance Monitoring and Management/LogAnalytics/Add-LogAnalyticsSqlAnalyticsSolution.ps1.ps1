<#
.SYNOPSIS
  Adds the Log Analytics 'Azure SQL Analytics' solution to the WTP Log Analytics workspace.   

.DESCRIPTION
  Adds the Log Analytics solution 'Azure SQL Analytics' for the WTP Log Analytics workspace.    

.PARAMETER WtpResourceGroupName
  The resource group name used during the deployment of the WTP app (case sensitive)

.PARAMETER WtpUser
  The 'User' value that was entered during the deployment of the WTP app

#>

Param(
    [Parameter(Mandatory=$true)]
    [string]$WtpResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$WtpUser
)

$WtpUser = $WtpUser.ToLower()

Import-Module $PSScriptRoot\..\..\Common\SubscriptionManagement -Force
Import-Module $PSScriptRoot\..\..\Common\CatalogAndDatabaseManagement -Force
Import-Module AzureRm.OperationalInsights

# Ensure logged in to Azure
Initialize-Subscription

$config = Get-Configuration

## MAIN SCRIPT ## ----------------------------------------------------------------------------

$workspaceName = $config.LogAnalyticsWorkspaceNameStem + $WtpUser

Set-AzureRmOperationalInsightsIntelligencePack `
    -ResourceGroupName $WtpResourceGroupName `
    -WorkspaceName $workspaceName `
    -IntelligencePackName "AzureSQLAnalytics" `
    -Enabled $true `
    > $null

Write-Output "Azure SQL Analytics solution added for workspace '$workspaceName'."