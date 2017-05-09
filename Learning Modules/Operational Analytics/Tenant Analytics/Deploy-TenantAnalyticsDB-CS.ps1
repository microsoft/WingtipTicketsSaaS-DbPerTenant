<#
.SYNOPSIS
  Creates a tenant analytics database with a columnstore table for ticket analytics data.

.DESCRIPTION
  Creates the tenant analytics database for result sets queries from Elastic jobs. 
  Database is created in the resource group created when the WTP application was deployed.

#>
param(
    [Parameter(Mandatory=$true)]
    [string]$WtpResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$WtpUser
)

Import-Module $PSScriptRoot\..\..\Common\SubscriptionManagement -Force
Import-Module $PSScriptRoot\..\..\WtpConfig -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription

$config = Get-Configuration

$catalogServerName = $($config.CatalogServerNameStem) + $WtpUser
$databaseName = $config.TenantAnalyticsCSDatabaseName
$fullyQualfiedCatalogServerName = $catalogServerName + ".database.windows.net"

# Check if Analytics database has already been created 
$TenantAnalyticsDatabaseName = Get-AzureRmSqlDatabase `
                -ResourceGroupName $WtpResourceGroupName `
                -ServerName $catalogServerName `
                -DatabaseName $databaseName `
                -ErrorAction SilentlyContinue


    if($TenantAnalyticsCSDatabaseName)
{
    Write-Output "Tenant Analytics Columnstore database '$databaseName' already exists."
    exit
}

Write-output "Initializing the columnstore database '$($config.TenantAnalyticsCSDatabaseName)'..."

# Create the tenant analytics database
New-AzureRmSqlDatabase `
    -ResourceGroupName $WtpResourceGroupName `
    -ServerName $catalogServerName `
    -DatabaseName $databaseName `
    -RequestedServiceObjectiveName "P1"

# Pre-create the tenant analytics columnstore table schema

$commandText = "
CREATE TABLE [dbo].[AllTicketsPurchasesfromAllTenants](
	[VenueId] [int] NULL,
	[VenueName] [nvarchar](50) NULL,
	[VenueType] [char](30) NULL,
	[VenuePostalCode] [char](10) NULL,
	[VenueCapacity] [int] NULL,
	[TicketPurchaseId] [int] NULL,
	[PurchaseDate] [datetime] NULL,
	[PurchaseTotal] [money] NULL,
	[CustomerId] [int] NULL,
	[CustomerPostalCode] [char](10) NULL,
	[CountryCode] [char](3) NULL,
	[EventId] [int] NULL,
	[EventName] [nvarchar](50) NULL,
	[EventSubtitle] [nvarchar](50) NULL,
	[EventDate] [datetime] NULL,
	[job_execution_id] [uniqueidentifier] NULL,
	[internal_execution_id] [uniqueidentifier] NULL
)
GO
CREATE CLUSTERED COLUMNSTORE INDEX cci_Tickets
ON [AllTicketsPurchasesfromAllTenants]
GO
"
Write-output "Initializing schema in '$databaseName'..."

Invoke-Sqlcmd `
    -ServerInstance $fullyQualfiedCatalogServerName `
    -Username $config.CatalogAdminUserName `
    -Password $config.CatalogAdminPassword `
    -Database $databaseName `
    -Query $commandText `
    -ConnectionTimeout 30 `
    -QueryTimeout 30 `
    -EncryptConnection
	
Write-Output "Deployment of tenant analytics columnstore database '$databaseName' and table schema completed."