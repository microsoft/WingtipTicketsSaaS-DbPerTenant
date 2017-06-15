[cmdletbinding()]

<#
 .SYNOPSIS
    Deploys an database for Ad-hoc query analytics

 .DESCRIPTION
    Deploys an an Operational Analytics database into which results from ad-hoc and scheduled queries for the 
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

$config = Get-Configuration

# Get Azure credentials if not already logged on. 
Initialize-Subscription

# Check resource group exists
$resourceGroup = Get-AzureRmResourceGroup -Name $WtpResourceGroupName -ErrorAction SilentlyContinue

if(!$resourceGroup)
{
    throw "Resource group '$WtpResourceGroupName' does not exist.  Exiting..."
}

$catalogServerName = $config.CatalogServerNameStem + $WtpUser
$fullyQualfiedCatalogServerName = $catalogServerName + ".database.windows.net"
$databaseName = $config.AdhocAnalyticsDatabaseName

# Check if Analytics database has already been created 
$adHocAnalyticsDB = Get-AzureRmSqlDatabase `
                -ResourceGroupName $WtpResourceGroupName `
                -ServerName $catalogServerName `
                -DatabaseName $databaseName `
                -ErrorAction SilentlyContinue

if($adHocAnalyticsDB)
{
    Write-Output "Ad-hoc Analytics database '$databaseName' already exists."
    exit
}

Write-output "Deploying Ad-hoc Analytics database '$databaseName' on catalog server '$catalogServerName'..."

# Deploy database for operational analytics 
New-AzureRmSqlDatabase `
        -ResourceGroupName $WtpResourceGroupName `
        -ServerName $catalogServerName `
        -DatabaseName $databaseName `
        -RequestedServiceObjectiveName $config.AdhocAnalyticsDatabaseServiceObjective `
        > $null
