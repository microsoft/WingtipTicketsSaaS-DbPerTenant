<#
.SYNOPSIS
  Creates an Operational Analytics DW database for tenant query data

.DESCRIPTION
  Creates the operational tenant analytics DW database for result sets queries from Elastic jobs. Database is created in the resource group
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

Import-Module $PSScriptRoot\..\..\AppVersionSpecific -Force

$config = Get-Configuration

$catalogServerName = $($config.CatalogServerNameStem) + $WtpUser
$databaseName = $config.TenantAnalyticsDWDatabaseName

# Check if Analytics DW database has already been created 
$TenantAnalyticsDWDatabaseName = Get-AzureRmSqlDatabase `
                -ResourceGroupName $WtpResourceGroupName `
                -ServerName $catalogServerName `
                -DatabaseName $databaseName `
                -ErrorAction SilentlyContinue

if($TenantAnalyticsDatabaseName)
{
    Write-Output "Tenant Analytics DW database '$databaseName' already exists."
    exit
}

Write-output "Initializing the DW database '$databaseName'..."

# Create the tenant analytics DW database
New-AzureRmSqlDatabase `
    -ResourceGroupName $WtpResourceGroupName `
    -ServerName $catalogServerName `
    -DatabaseName $databaseName `
    -RequestedServiceObjectiveName "DW400"
