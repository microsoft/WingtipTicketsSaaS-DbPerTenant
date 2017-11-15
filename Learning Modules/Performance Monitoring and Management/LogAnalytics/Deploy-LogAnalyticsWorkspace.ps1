[cmdletbinding()]

<#
 .SYNOPSIS
    Deploys a Log Analytics Workspace

 .DESCRIPTION
    Deploys a Log Analytics Workspace into which diagnostics for the 
    WTP applications will be collected .

 .PARAMETER WtpResourceGroupName
    The name of the resource group in which the WTP application is deployed.

 .PARAMETER WtpUser
    # The 'User' value entered during the deployment of the WTP application.
#>
param(
    [Parameter(Mandatory=$True)]
    [string] $WtpResourceGroupName,

    [Parameter(Mandatory=$True)]
    [string] $WtpUser
 )

$ErrorActionPreference = "Stop" 

Import-Module $PSScriptRoot\..\..\Common\SubscriptionManagement -Force
Import-Module $PSScriptRoot\..\..\WtpConfig -Force
Import-Module AzureRm.OperationalInsights 


$config = Get-Configuration

# Get Azure credentials if not already logged on. 
Initialize-Subscription

# Register the Log Analytics resource provider
Register-AzureRmResourceProvider -ProviderNamespace "microsoft.operationalinsights" > $null

# Check resource group exists
$resourceGroup = Get-AzureRmResourceGroup -Name $WtpResourceGroupName -ErrorAction SilentlyContinue

if(!$resourceGroup)
{
    throw "Resource group '$WtpResourceGroupName' does not exist.  Exiting..."
}

$workspaceName = ($config.LogAnalyticsWorkspaceNameStem + $WtpUser)

$workspace = Get-AzureRmOperationalInsightsWorkspace `
    -ResourceGroupName $WtpResourceGroupName `
    -Name $workspaceName `
    -ErrorAction SilentlyContinue

if($workspace)
{
    Write-Output "Log Analytics workspace '$workspaceName' already exists."
    exit
}

Write-output "Deploying Log Analytics workspace '$workspaceName'..."

# deploy log analytics workspace (locations are currently restricted so a fixed location is used )
New-AzureRmResourceGroupDeployment `
        -ResourceGroupName $WtpResourceGroupName `
        -TemplateFile ($PSScriptRoot + "\" + $config.LogAnalyticsWorkspaceTemplate) `
        -Name "LogAnalyticsWorkspaceDeployment" `
        -Location $config.LogAnalyticsDeploymentLocation `
        -WorkspaceName $workspaceName `
        -Sku "free" `
        -Verbose `
        -ErrorAction Stop `
        > $null

Write-Output "Deployment of Log Analytics Workspace '$workspaceName' complete."
