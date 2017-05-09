<#
.SYNOPSIS
  Creates an Operational Analytics database for adhoc query data

.DESCRIPTION
  Creates the operational analytics database for result sets adhoc queries for Elastic Query. Database is created in the resource group
  created when the WTP application was deployed.

#>
param(
    [Parameter(Mandatory=$true)]
    [string]$WtpResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$WtpUser
)

Import-Module $PSScriptRoot\..\..\Common\SubscriptionManagement -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription

Import-Module $PSScriptRoot\..\..\WtpConfig -Force

$config = Get-Configuration

$catalogServerName = $($config.CatalogServerNameStem) + $WtpUser
$fullyQualfiedCatalogServerName = $catalogServerName + ".database.windows.net"
$databaseName = $config.TenantAnalyticsDatabaseName

# Check if Analytics database has already been created 
$TenantAnalyticsDatabaseName = Get-AzureRmSqlDatabase `
                -ResourceGroupName $WtpResourceGroupName `
                -ServerName $catalogServerName `
                -DatabaseName $databaseName `
                -ErrorAction SilentlyContinue

if($TenantAnalyticsDatabaseName)
{
    Write-Output "Tenant Analytics database '$databaseName' already exists."
    exit
}

Write-output "Initializing the database '$($config.TenantAnalyticsDatabaseName)'..."

# Create the tenant analytics database
New-AzureRmSqlDatabase `
    -ResourceGroupName $WtpResourceGroupName `
    -ServerName $catalogServerName `
    -DatabaseName $databaseName `
    -RequestedServiceObjectiveName "S0"
