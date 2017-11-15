[cmdletbinding()]

<#
 .SYNOPSIS
    Deploys the Ad-hoc Analytics database, used for distributed query across tenant databases
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
$AdhocAnalyticsDatabaseName = $config.AdhocReportingDatabaseName

# Check if Ad-hoc Analytics database already exists 
$adHocAnalyticsDB = Get-AzureRmSqlDatabase `
                -ResourceGroupName $WtpResourceGroupName `
                -ServerName $catalogServerName `
                -DatabaseName $AdhocAnalyticsDatabaseName `
                -ErrorAction SilentlyContinue

if($adHocAnalyticsDB)
{
    Write-Output "Ad-hoc Reporting database '$AdhocAnalyticsDatabaseName' already exists."

    # it is assumed that if the database is present it is initialized, so script exits at this point 
    exit
}

Write-output "Deploying database '$AdhocAnalyticsDatabaseName' on server '$catalogServerName'..."

# Deploy adhoc reporting database 
New-AzureRmSqlDatabase `
        -ResourceGroupName $WtpResourceGroupName `
        -ServerName $catalogServerName `
        -DatabaseName $AdhocAnalyticsDatabaseName `
        -RequestedServiceObjectiveName $config.AdhocReportingDatabaseServiceObjective `
        > $null

# if schema deployment is requested... 
if($DeploySchema.IsPresent)
{
    $commandText = [IO.File]::ReadAllText("$PSScriptRoot\Initialize-AdhocReportingDB.sql")

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
