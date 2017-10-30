[cmdletbinding()]

<#
 .SYNOPSIS
    Deploys an database for Ad-hoc query analytics

 .DESCRIPTION
    Deploys the Adhoc Analytics database to be used with Elastic Query for distributing queries across tenant databases.

 .PARAMETER WtpResourceGroupName
    The name of the resource group in which the Wingtip SaaS application is deployed.

 .PARAMETER WtpUser
    # The 'User' value entered during the deployment of the Wingtip SaaS application.
#>
param(
    [Parameter(Mandatory=$true)]
    [string] $WtpResourceGroupName,

    [Parameter(Mandatory=$true)]
    [string] $WtpUser,

    [Parameter(Mandatory=$false)]
    [switch] $DeploySchema
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
$fullyQualifiedCatalogServerName = $catalogServerName + ".database.windows.net"
$AdhocAnalyticsDatabaseName = $config.AdhocAnalyticsDatabaseName

# Check if Ad-hoc Analytics database already exists 
$adHocAnalyticsDB = Get-AzureRmSqlDatabase `
                -ResourceGroupName $WtpResourceGroupName `
                -ServerName $catalogServerName `
                -DatabaseName $AdhocAnalyticsDatabaseName `
                -ErrorAction SilentlyContinue

if($adHocAnalyticsDB)
{
    Write-Output "Ad-hoc Analytics database '$AdhocAnalyticsDatabaseName' already exists."

    # it is assumed that if the database is present it is initialized, so script exits at this point 
    exit
}

Write-output "Deploying database '$AdhocAnalyticsDatabaseName' on server '$catalogServerName'..."

# Deploy adhoc analytics database 
New-AzureRmSqlDatabase `
        -ResourceGroupName $WtpResourceGroupName `
        -ServerName $catalogServerName `
        -DatabaseName $AdhocAnalyticsDatabaseName `
        -RequestedServiceObjectiveName $config.AdhocAnalyticsDatabaseServiceObjective `
        > $null

# if schema deployment is requested... 
if($DeploySchema.IsPresent)
{
    $commandText = [IO.File]::ReadAllText("$PSScriptRoot\Initialize-AdhocAnalyticsDb.sql")

    Write-output "Initializing database schema..."
	  
	Invoke-SqlcmdWithRetry `
    -ServerInstance $fullyQualifiedCatalogServerName `
	-Username $config.CatalogAdminUserName `
    -Password $config.CatalogAdminPassword `
	-Database $AdhocAnalyticsDatabaseName `
	-Query $commandText `
	-ConnectionTimeout 30 `
	-QueryTimeout 30 `
    > $null

}

Write-output "Database '$AdhocAnalyticsDatabaseName' deployed on server '$catalogServerName'."