<#
.SYNOPSIS
  Creates an Operational Analytics database for tenant query data

.DESCRIPTION
  Creates the operational tenant analytics database for result sets queries from Elastic jobs. Database is created in the resource group
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

$databaseName = $config.TenantAnalyticsDatabaseName

# Check if Analytics database has already been created 
$TenantAnalyticsDatabase = Get-AzureRmSqlDatabase `
                -ResourceGroupName $WtpResourceGroupName `
                -ServerName $catalogServerName `
                -DatabaseName $databaseName `
                -ErrorAction SilentlyContinue

if($TenantAnalyticsDatabase)
{
    Write-Output "Database '$databaseName' already exists."
    exit
}

Write-output "Deploying the database '$databaseName' to server '$catalogServerName' ..."

# Create the tenant analytics database
New-AzureRmSqlDatabase `
    -ResourceGroupName $WtpResourceGroupName `
    -ServerName $catalogServerName `
    -DatabaseName $databaseName `
    -RequestedServiceObjectiveName "S0" `
    > $null
