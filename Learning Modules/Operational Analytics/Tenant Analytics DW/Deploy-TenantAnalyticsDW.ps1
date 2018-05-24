<#
.SYNOPSIS
  Creates an Analytics data warehouse for tenant query data

.DESCRIPTION
  Creates the tenant analytics data warehouse in the resource group
  created when the Wingtip Tickets application was deployed.

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
$dataWarehouseName = $config.TenantAnalyticsDWDatabaseName

# Check if Analytics DW database has already been created 
$TenantAnalyticsDWDatabase = Get-AzureRmSqlDatabase `
                -ResourceGroupName $WtpResourceGroupName `
                -ServerName $catalogServerName `
                -DatabaseName $dataWarehouseName `
                -ErrorAction SilentlyContinue

if($TenantAnalyticsDWDatabase)
{
    Write-Output "`nData warehouse '$dataWarehouseName' already exists."
    exit
}

Write-output "`nDeploying data warehouse '$dataWarehouseName'..."

# Create the tenant analytics DW database
New-AzureRmSqlDatabase `
    -ResourceGroupName $WtpResourceGroupName `
    -ServerName $catalogServerName `
    -DatabaseName $dataWarehouseName `
    -RequestedServiceObjectiveName "DW400" `
    > $null

# Creating tables in tenant analytics database
$commandText = "
-- Create table for storing raw tickets data. 
-- Tables for raw data contain an identity column for tracking purposes.
IF (OBJECT_ID('raw_Tickets')) IS NOT NULL DROP TABLE raw_Tickets
CREATE TABLE [dbo].[raw_Tickets](
	[RawTicketId] int identity(1,1) NOT NULL,
	[VenueId] [int] NULL,
	[CustomerEmailId] [int] NULL,
	[TicketPurchaseId] [int] NULL,
	[PurchaseDate] [datetime] NULL,
	[PurchaseTotal] [money] NULL,
	[EventId] [int] NULL,
	[RowNumber] [int] NULL,
	[SeatNumber] [int] NULL
)
GO

-- Create table for storing raw customer data. 
IF (OBJECT_ID('raw_Customers')) IS NOT NULL DROP TABLE raw_Customers
CREATE TABLE [dbo].[raw_Customers](
    [RawCustomerId] int identity(1,1) NOT NULL,
    [VenueId] [int] NULL,
    [CustomerEmailId] [int] NULL,
    [CustomerPostalCode] [char](10) NULL,
    [CustomerCountryCode] [char](3) NULL
)
GO

-- Create table for storing raw events data. 
IF (OBJECT_ID('raw_Events')) IS NOT NULL DROP TABLE raw_Events
CREATE TABLE [dbo].[raw_Events](
    [RawEventId] int identity(1,1) NOT NULL,
    [VenueId] [int] NULL,
    [EventId] [int] NULL,
    [EventName] [nvarchar](50) NULL,
    [EventSubtitle] [nvarchar](50) NULL,
    [EventDate] [datetime] NULL
)
GO

-- Create table for storing raw venues data. 
IF (OBJECT_ID('raw_Venues')) IS NOT NULL DROP TABLE raw_Venues
CREATE TABLE [dbo].[raw_Venues](
    [RawVenueId] int identity(1,1) NOT NULL,
    [VenueId] [int] NULL,
    [VenueName] [nvarchar](50) NULL,
    [VenueType] [char](30) NULL,
    [VenuePostalCode] [char](10) NULL,
    [VenueCountryCode] [char](3) NULL,
    [VenueCapacity] [int] NULL
)
GO

-- Create fact and dimension tables for the star-schema.
-- Create a dimension table for even in tenantanalytics database.ts.
-- Dimension tables use a surrogate key.
IF (OBJECT_ID('dim_Events')) IS NOT NULL DROP TABLE dim_Events
CREATE TABLE [dbo].[dim_Events] 
    ([SK_EventId] int identity(1,1) NOT NULL,
    [VenueId] [int] NULL,
    [EventId] [int] NULL,
    [EventName] [nvarchar](50) NULL,
    [EventSubtitle] [nvarchar](50) NULL,
    [EventDate] [datetime] NULL
)
GO

-- Create a dimension table for venues.
IF (OBJECT_ID('dim_Venues')) IS NOT NULL DROP TABLE dim_Venues
CREATE TABLE [dbo].[dim_Venues] 
    ([SK_VenueId] int identity(1,1) NOT NULL,
    [VenueId] [int] NOT NULL,
    [VenueName] [nvarchar](50) NOT NULL,
    [VenueType] [char](30) NOT NULL,
    [VenueCapacity] [int] NOT NULL,
    [VenuepostalCode] [char](10) NULL,
    [VenueCountryCode] [char](3) NOT NULL
)
GO

-- Create a dimension table for customers. 
IF (OBJECT_ID('dim_Customers')) IS NOT NULL DROP TABLE dim_Customers
CREATE TABLE [dbo].[dim_Customers] 
    ([SK_CustomerId] int identity(1,1) NOT NULL,
    [VenueId] [int] NULL,
    [CustomerEmailId] [int] NULL,
    [CustomerPostalCode] [char](10) NULL,
    [CustomerCountryCode] [char](3) NULL
)
GO

-- Create and populate a dimension table for dates.
IF (OBJECT_ID('dim_Dates')) IS NOT NULL DROP TABLE dim_Dates;
CREATE TABLE dim_Dates
WITH (DISTRIBUTION = REPLICATE)
AS 
WITH BaseData AS (SELECT A=0 UNION ALL SELECT A=1 UNION ALL SELECT A=2 UNION ALL SELECT A=3 UNION ALL SELECT A=4 UNION ALL SELECT A=5 UNION ALL SELECT A=6 UNION ALL SELECT A=7 UNION ALL SELECT A=8 UNION ALL SELECT A=9)
,DateSeed AS (SELECT RID = ROW_NUMBER() OVER (ORDER BY A.A) FROM BaseData A CROSS APPLY BaseData B CROSS APPLY BaseData C CROSS APPLY BaseData D CROSS APPLY BaseData E)
,DateBase AS (SELECT TOP 18628 DateValue = cast(DATEADD(D, RID,'1979-12-31')AS DATE) FROM DateSeed)
SELECT DateID = cast(replace(cast(DateValue as varchar(25)),'-','')as int),
    DateValue = cast(DateValue as date),
    DateYear = DATEPART(year, DateValue),
    DateMonth = DATEPART(month, DateValue),
    DateDay = DATEPART(day, DateValue),
    DateDayOfYear = DATEPART(dayofyear, DateValue),
    DateWeekday = DATEPART(weekday, DateValue),
    DateWeek = DATEPART(week, DateValue),
    DateQuarter = DATEPART(quarter, DateValue),
    DateMonthName = DATENAME(month, DateValue),
    DateQuarterName = 'Q'+DATENAME(quarter, DateValue),
    DateWeekdayName = DATENAME(weekday, DateValue),
    MonthYear = LEFT(DATENAME(month, DateValue),3)+'-'+DATENAME(year, DateValue)  
FROM DateBase;

-- Create a tickets fact table in tenantanalytics database 
IF (OBJECT_ID('fact_Tickets')) IS NOT NULL DROP TABLE fact_Tickets
CREATE TABLE [dbo].[fact_Tickets] 
    ([TicketPurchaseId] [int] NOT NULL,
    [SK_EventId] [int] NOT NULL,
    [SK_CustomerId] [int] NOT NULL,
    [SK_VenueId] [int] NOT NULL,
    [DateID] [int] NOT NULL,
    [PurchaseTotal] [money] NOT NULL,
    [SaleDay] [int] NOT NULL,
    [RowNumber] [int] NOT NULL,
    [SeatNumber] [int] NOT NULL)
GO 

-- Create a stored procedure that populates the star-schema tables. 
IF (OBJECT_ID('sp_TransformRawData')) IS NOT NULL DROP PROCEDURE sp_TransformRawData
GO

CREATE PROCEDURE sp_TransformRawData 
AS
BEGIN

-- Get the maximum value from the tracking column and then transform rows < max value.
DECLARE @StagingVenueLastInsert int = (SELECT MAX(RawVenueId) FROM [dbo].[raw_Venues]);

-- Upsert pattern: 
-- As a best practice, avoid using UPDATE statements for SQL Data Warehouse loading. 
-- Instead, use a temporary table and insert statements.
-- Create a table temporarily and insert existing rows that were not changed and 
-- modified rows, explicitly inserting the identity column values from the dimension table.
-- Next, insert into the table all the new rows automatically generating the surrogate key 
-- defined by identity. Next, rename the current dimension table as an archive table and 
-- rename the temporary table to be the dimension table. As a best practice, save the archived 
-- table until the next incremental run.

-----------------------------------------------------------------
----------------Venue DIMENSION----------------------------------
-----------------------------------------------------------------
-- Create a temporary table to hold the existing non-modified rows 
-- in the dimension table, the modified rows and the new rows.
CREATE TABLE dim_Venue_temp 
    ([SK_VenueId] int identity(1,1) NOT NULL,
    [VenueId] [int] NULL,
    [VenueName] [nvarchar](50) NULL,
    [VenueType] [char](30) NULL,
    [VenueCapacity] [int] NULL,
    [VenuepostalCode] [char](10) NULL,
    [VenueCountryCode] [char](3) NULL
)

-- Allow values to be inserted explicitly in the identity column
-- to ensure that all existing rows get the same identity value.
SET IDENTITY_INSERT dim_Venue_temp ON;

--Insert existing and modified rows in the temporary table.
INSERT INTO dim_Venue_temp (SK_VenueId , VenueId, VenueName, VenueType, VenueCapacity, VenuepostalCode, VenueCountryCode)
-- Existing rows in the dimension table that are not modified
SELECT c2.SK_VenueId,
       c2.VenueId,
       c2.VenueName,
       c2.VenueType,
       c2.VenueCapacity,
       c2.VenuepostalCode,
       c2.VenueCountryCode
FROM [dbo].[dim_Venues] AS c2
WHERE c2.VenueId NOT IN
(   SELECT  t2.VenueId
    FROM     [dbo].[raw_Venues] t2
    WHERE   t2.RawVenueId <= @StagingVenueLastInsert
)
UNION ALL
-- All modified rows
SELECT DISTINCT c.SK_VenueId,     -- Surrogate key from the dimension table
                t.VenueId,
                t.VenueName, 
                t.VenueType,
                t.VenueCapacity,
                t.VenuepostalCode,
                t.VenueCountryCode
FROM [dbo].[dim_Venues] AS c
INNER JOIN [dbo].[raw_Venues] AS t ON  t.VenueId = c.VenueId
WHERE   t.RawVenueId <= @StagingVenueLastInsert

--Turn off identity_insert to automatically generate surrogate keys for the new rows
SET IDENTITY_INSERT dim_Venue_temp OFF;

-- Insert all the new rows in the staging table.
INSERT INTO dim_Venue_temp (VenueId, VenueName, VenueType, VenueCapacity, VenuepostalCode, VenueCountryCode)
SELECT DISTINCT t.VenueId,
                t.VenueName, 
                t.VenueType,
                t.VenueCapacity,
                t.VenuepostalCode,
                t.VenueCountryCode
FROM      [dbo].[raw_Venues] AS t
WHERE t.RawVenueId <= @StagingVenueLastInsert
AND VenueId NOT IN
(SELECT VenueId
 FROM [dbo].[dim_Venues]
) 

-- Delete the archived dimension table if it exists.
IF OBJECT_ID('last_dim_Venues') IS NOT NULL DROP TABLE last_dim_Venues; 

-- Rename the current dimension table to be the archive table
-- and the temporary table to be the new dimension table.
RENAME OBJECT dim_Venues TO last_dim_Venues
RENAME OBJECT dim_Venue_temp TO dim_Venues

-----------------------------------------------------------------
----------------Event DIMENSION----------------------------------
-----------------------------------------------------------------
DECLARE @StagingEventLastInsert int = (SELECT MAX(RawEventId) FROM  [dbo].[raw_Events])

-- Create a temporary table to hold the existing non-modified rows 
-- in the dimension table, the modified rows and the new rows.
CREATE TABLE dim_Event_temp 
    ([SK_EventId] int identity(1,1) NOT NULL,
    [VenueId] [int] NULL,
    [EventId] [int] NULL,
    [EventName] [nvarchar](50) NULL,
    [EventSubtitle] [nvarchar](50) NULL,
    [EventDate] [datetime] NULL
)

-- Allow values to be inserted explicitly in the identity column
-- to ensure that all existing rows get the same identity value.
SET IDENTITY_INSERT dim_Event_temp ON;

--Insert existing and modified rows in the temporary table.
INSERT INTO dim_Event_temp (SK_EventId , VenueId, EventId, EventName, EventSubtitle, EventDate)
--DECLARE @StagingEventLastInsert int = (SELECT MAX(RawEventId) FROM  [dbo].[raw_Events])
-- Existing rows in the dimension table that are not modified
SELECT c.[SK_EventId],
       c.[VenueId],
       c.[EventId],
       c.[EventName],
       c.[EventSubtitle],
       c.[EventDate]
FROM [dbo].[dim_Events] AS c
WHERE CONCAT(c.VenueId, c.EventId) NOT IN 
(SELECT  CONCAT(t.VenueId, t.EventId)
 FROM     [dbo].[raw_Events] t
 WHERE   t.RawEventId <= @StagingEventLastInsert
)

UNION ALL

-- All modified rows
SELECT DISTINCT c.[SK_EventId],
                t.[VenueId],
                t.[EventId],
                t.[EventName],
                t.[EventSubtitle],
                t.[EventDate]
FROM [dbo].[dim_Events] AS c
INNER JOIN [dbo].[raw_Events] AS t ON  t.VenueId = c.VenueId AND t.EventId = c.EventId
WHERE   t.RawEventId <= @StagingEventLastInsert

--Turn off identity_insert to automatically generate surrogate keys for the new rows.
SET IDENTITY_INSERT dim_Event_temp OFF;

-- New rows in staging table. 
INSERT INTO dim_Event_temp (VenueId, EventId, EventName, EventSubtitle, EventDate)
SELECT DISTINCT t.[VenueId],
                t.[EventId],
		t.[EventName],
		t.[EventSubtitle],
		t.[EventDate]
FROM [dbo].[raw_Events] AS t
WHERE t.RawEventId <= @StagingEventLastInsert
AND CONCAT(VenueId, EventId) NOT IN
    (SELECT   Concat(VenueId, EventId)
     FROM      [dbo].[dim_Events]
    ) 

-- Delete the archived dimension table if it exists.
IF OBJECT_ID('last_dim_Events') IS NOT NULL DROP TABLE last_dim_Events; 

-- Rename the current dimension table to be the archive table
-- and the temporary table to be the new dimension table.
RENAME OBJECT dim_Events TO last_dim_Events
RENAME OBJECT dim_Event_temp TO dim_Events

-----------------------------------------------------------------
----------------CUSTOMER DIMENSION-------------------------------
-----------------------------------------------------------------
DECLARE @StagingCustomerLastInsert int = (SELECT MAX(RawCustomerId) FROM  [dbo].[raw_Customers]);

-- Create a temporary table to hold the existing non-modified rows 
-- in the dimension table, the modified rows and the new rows.
CREATE TABLE dim_Customer_temp 
    ([SK_CustomerId] int identity(1,1) NOT NULL,
    [VenueId] int NOT NULL,
    [CustomerEmailId] [int] NULL,
    [CustomerPostalCode] [char](10) NULL,
    [CustomerCountryCode] [char](3) NULL
)

-- Allow values to be inserted explicitly in the identity column
-- to ensure that all existing rows retain the same surrogate key value
SET IDENTITY_INSERT dim_Customer_temp ON;

-- Insert existing and modified rows in the temporary table.
INSERT INTO dim_Customer_temp (SK_CustomerId , VenueId, CustomerEmailId, CustomerPostalCode, CustomerCountryCode)
-- Existing rows in the dimension table that are not modified
SELECT c.SK_CustomerId,
       c.VenueId,
       c.CustomerEmailId,
       c.CustomerPostalCode,
       c.CustomerCountryCode
FROM [dbo].[dim_Customers] AS c
WHERE CONCAT(c.VenueId, c.CustomerEmailId) NOT IN
(   SELECT  CONCAT(t.VenueId, t.CustomerEmailId)
    FROM     [dbo].[raw_Customers] t
    WHERE   t.RawCustomerId <= @StagingCustomerLastInsert
)
UNION ALL
-- All modified rows
SELECT DISTINCT c.SK_CustomerId,     -- Surrogate key taken from the dimension table
                t.VenueId,
                t.CustomerEmailId,
                t.CustomerPostalCode, 
	        t.CustomerCountryCode
FROM [dbo].[dim_Customers] AS c
INNER JOIN [dbo].[raw_Customers] AS t ON  t.CustomerEmailId = c.CustomerEmailId AND t.VenueId = c.VenueId
WHERE   t.RawCustomerId <= @StagingCustomerLastInsert

-- Turn off identity_insert to autmatically generate surrogate keys for the new rows
SET IDENTITY_INSERT dim_Customer_temp OFF;

-- New rows in staging table 
INSERT INTO dim_Customer_temp (VenueId, CustomerEmailId, CustomerPostalCode, CustomerCountryCode)
SELECT DISTINCT t.VenueId,
                t.CustomerEmailId,
                t.CustomerPostalCode, 
	        t.CustomerCountryCode
FROM      [dbo].[raw_Customers] AS t
WHERE t.RawCustomerId <= @StagingCustomerLastInsert
AND CONCAT(VenueId, CustomerEmailId) NOT IN
	(SELECT CONCAT(VenueId, CustomerEmailId)
	 FROM   [dbo].[dim_Customers]
	) 

-- Delete the archived dimension table if it exists.
IF OBJECT_ID('last_dim_Customers') IS NOT NULL DROP TABLE last_dim_Customers;

-- Rename the current dimension table to be the archive table
-- and the temporary table to be the new dimension table.
RENAME OBJECT dim_Customers TO last_dim_Customers
RENAME OBJECT dim_Customer_temp TO dim_Customers

-----------------------------------------------------------------
----------------TICKETS FACTS------------------------------------
-----------------------------------------------------------------
DECLARE @StagingTicketLastInsert int = (SELECT MAX(RawTicketId) FROM  [dbo].[raw_Tickets]);

-- Merge tickets from raw data to the fact table
CREATE TABLE [dbo].[stage_fact_Tickets]
WITH (DISTRIBUTION = HASH(SK_VenueID),
  CLUSTERED COLUMNSTORE INDEX)
AS
-- Get new rows
SELECT DISTINCT t.TicketPurchaseId, 
                e.SK_EventId,
		c.SK_CustomerId,
		v.SK_VenueId,
		d.DateID,
		t.PurchaseTotal,
		SaleDay = 60 - DATEDIFF(d, CAST(t.PurchaseDate AS DATE), CAST(e.EventDate AS DATE)),
		t.RowNumber,
		t.SeatNumber
FROM [dbo].[raw_Tickets] AS t
INNER JOIN [dbo].[dim_Events] e on t.EventId = e.EventId AND t.VenueId = e.VenueId
INNER JOIN [dbo].[dim_Venues] v on t.VenueID = v.VenueId
INNER JOIN [dbo].[dim_Customers] c on t.CustomerEmailId = c.CustomerEmailId AND t.VenueId = c.VenueId
INNER JOIN [dbo].[dim_Dates] d on CAST(t.PurchaseDate AS DATE) = d.DateValue
WHERE RawTicketId <= @StagingTicketLastInsert
UNION ALL  
-- Union all with unmodified rows
SELECT ft.TicketPurchaseId, ft.SK_EventId, ft.SK_CustomerId, ft.SK_VenueID, ft.DateID, ft.PurchaseTotal, ft.SaleDay, ft.RowNumber, ft.SeatNumber
FROM      [dbo].[fact_Tickets] AS ft
WHERE CONCAT(TicketPurchaseId, SK_VenueId, SK_EventId) NOT IN
(   SELECT   CONCAT(TicketPurchaseId, VenueId, EventId)
    FROM [dbo].[raw_Tickets] t
    --INNER JOIN [dbo].[raw_Events] ve on t.VenueId = ve.VenueId AND t.EventId = ve.EventId 
    WHERE RawTicketId <= @StagingTicketLastInsert 
);

-- If the archived fact table exists delete it.
IF OBJECT_ID('[dbo].[last_fact_Tickets]') IS NOT NULL  
DROP TABLE [dbo].[last_fact_Tickets];

-- Rename the current fact table to the last fact table and rename the staging table to be the current fact table.
RENAME OBJECT [dbo].[fact_Tickets] TO last_fact_Tickets;
RENAME OBJECT dbo.[stage_fact_Tickets] TO [fact_Tickets];

END
;

-- Delete the rows in the staging table that are already transformed
DELETE FROM raw_Tickets
WHERE RawTicketId <= @StagingTicketLastInsert 

DELETE FROM [dbo].[raw_Events]
WHERE RawEventId <= @StagingEventLastInsert 

DELETE FROM [dbo].[raw_Venues]
WHERE RawVenueId <= @StagingVenueLastInsert 

DELETE FROM [dbo].[raw_Customers]
WHERE RawCustomerId <= @StagingCustomerLastInsert 
GO
"

$catalogServerName = $config.catalogServerNameStem + $WtpUser
$fullyQualifiedCatalogServerName = $catalogServerName + ".database.windows.net"

Write-output "Deploying data warehouse schema..."

Invoke-SqlcmdWithRetry `
    -ServerInstance $fullyQualifiedCatalogServerName `
    -Username $config.CatalogAdminUserName `
    -Password $config.CatalogAdminPassword `
    -Database $dataWarehouseName `
    -Query $commandText `
    -ConnectionTimeout 30 `
    -QueryTimeout 30 `
    > $null  

$tenantsServerName = $($config.TenantServerNameStem) + $WtpUser 
$fullyQualifiedTenantServerName = $tenantsServerName + ".database.windows.net"

$databaseName = $config.TenantAnalyticsDWDatabaseName
$storagelocation = $config.AdfConfigStorageLocation
$containerName = $config.AdfConfigContainerName

$storageAccountName = $config.AdfStorageAccountNameStem + $WtpUser

# Create a storage account and upload the configuration file in it.

try 
{
    $storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $WtpResourceGroupName -Name $storageAccountName
}
catch 
{
    # Creating a storage account for data staging and for saving any additional configuration files required by Azure Data Factory
    Write-Output "Deploying storage account '$storageAccountName'..."

    $storageAccount = New-AzureRmStorageAccount -ResourceGroupName $WtpResourceGroupName `
        -Name $storageAccountName `
        -Location $storagelocation `
        -SkuName Standard_LRS `
        -Kind Storage
        
    $ctx = $storageAccount.Context

    Write-Output "Deploying configuration container in the storage account..."
    
    # Create a container in the storage account
    New-AzureStorageContainer `
        -Name $containerName `
        -Context $ctx `
        -Permission blob `
        > $null

    Write-Output "Uploading configuration file to storage..."

    # Upload config file containing names and structures of source and destination tables, columns names for the source table, 
    # source tracker column name and mapping between the source and destination table.
    Set-AzureStorageBlobContent `
        -File "$PSScriptRoot\TableConfig.json" `
        -Container $containerName `
        -Blob "TableConfig.json" `
        -Context $ctx `
        > $null 

}

# Get the account key for the storage account.
$storagekey = (Get-AzureRmStorageAccountKey -ResourceGroupName $WtpResourceGroupName -AccountName $storageAccount.StorageAccountName).Value[0]

# Creating connection strings SQL Database, Data Warehouse and Blob Storage.
$dbconnection = "Server=tcp:" + $fullyQualifiedTenantServerName + ",1433;Database=@{linkedService().DBName};User ID=" + $config.TenantAdminUserName + "@" + $tenantsServerName + ";Password=" + $config.TenantAdminPassword + ";Trusted_Connection=False;Encrypt=True;Connection Timeout=90"
$dwconnection = "Server=tcp:" + $fullyQualifiedCatalogServerName + ",1433;Database=@{linkedService().DBName};User ID=" + $config.CatalogAdminUserName + "@" + $catalogServerName + ";Password=" + $config.TenantAdminPassword + ";Trusted_Connection=False;Encrypt=True;Connection Timeout=90"
$storageconnection = "DefaultEndpointsProtocol=https;AccountName=" + $storageAccount.StorageAccountName + ";AccountKey=" + $storagekey

# Converting to secure string
$secureStringdbconnection = ConvertTo-SecureString $dbconnection -AsPlainText -Force
$secureStringdwconnection = ConvertTo-SecureString $dwconnection -AsPlainText -Force
$secureStringstorageconnection = ConvertTo-SecureString $storageconnection -AsPlainText -Force

$dataFactoryName = $config.DataFactoryNameStem + $WtpUser

Write-Output "Deploying data factory '$dataFactoryName'..."

# Deploy a data factory in the same resource group used for the application. If the data factory already exists, a message will appear asking if you want to replace it.
Set-AzureRmDataFactoryV2 `
    -ResourceGroupName $WtpResourceGroupName `
    -Location $config.DataFactoryLocation `
    -Name $dataFactoryName `
    > $null

Write-Output "Deploying data factory objects..."

# Deploying ARM template containing Azure Data Factory objects including pipelines, linked services, and datasets.
try 
{
    $deployment = New-AzureRmResourceGroupDeployment `
            -TemplateFile ($PSScriptRoot + "\" + $config.DataFactoryDeploymentTemplate) `
            -ResourceGroupName $WtpResourceGroupName `
            -factoryName $dataFactoryName `
            -AzureSqlDatabase_connectionString $secureStringdbconnection `
            -AzureSqlDataWarehouse_connectionString $secureStringdwconnection `
            -AzureStorage_connectionString $secureStringstorageconnection `
            -ErrorAction Stop 
}
catch 
{
        Write-Error $_.Exception.Message
        Write-Error "An error occured deploying the Azure Data Factory objects "
        throw
}

Write-Output "`nDeployment complete"
