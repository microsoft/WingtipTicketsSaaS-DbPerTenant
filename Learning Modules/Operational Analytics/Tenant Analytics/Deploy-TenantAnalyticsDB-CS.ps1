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
    -RequestedServiceObjectiveName "P1" `
    > $null

# Set up the tenant analytics database schema with a columnstore index on the fact table.

$commandText = "
-- Create table for storing raw tickets data. 
IF (OBJECT_ID('TicketsRawData')) IS NOT NULL DROP TABLE TicketsRawData
CREATE TABLE [dbo].[TicketsRawData](
	[TicketPurchaseId] [int] NOT NULL,
	[CustomerEmailId] [int] NOT NULL,
	[VenueId] [int] NOT NULL,
	[CustomerPostalCode] [char](10) NOT NULL,
	[CustomerCountryCode] [char](3) NOT NULL,
	[EventId] [int] NOT NULL,
	[RowNumber] [int] NOT NULL,
	[SeatNumber] [int] NOT NULL,
	[PurchaseTotal] [money] NOT NULL,
	[PurchaseDate] [datetime] NOT NULL,
	[internal_execution_id] [uniqueidentifier] NULL,
	[RawTicketId] int identity(1,1) NOT NULL
)
CREATE CLUSTERED COLUMNSTORE INDEX cci_RawTickets
ON [TicketsRawData]
GO

--Create table for storing raw venues and events data. 
IF (OBJECT_ID('EventsRawData')) IS NOT NULL DROP TABLE EventsRawData
CREATE TABLE [dbo].[EventsRawData](
	[VenueId] [int] NULL,
	[VenueName] [nvarchar](50) NULL,
	[VenueType] [char](30) NULL,
	[VenuePostalCode] [char](10) NULL,
    [VenueCountryCode] [char](3) NULL,
	[VenueCapacity] [int] NULL,
	[EventId] [int] NULL,
	[EventName] [nvarchar](50) NULL,
	[EventSubtitle] [nvarchar](50) NULL,
	[EventDate] [datetime] NULL,
	[internal_execution_id] [uniqueidentifier] NULL,
	[RawVenueEventId] int identity(1,1) NOT NULL
)
CREATE CLUSTERED COLUMNSTORE INDEX cci_RawVenuesEvents
ON [EventsRawData]
GO

--Create fact and dimension tables for the star-schema

-- Create an event dimension table in tenantanalytics database 
IF (OBJECT_ID('dim_Events')) IS NOT NULL DROP TABLE dim_Events
CREATE TABLE [dbo].[dim_Events] 
						([VenueId] [int] NOT NULL,
						[EventId] [int] NOT NULL,
						[EventName] [nvarchar](50) NOT NULL,
						[EventSubtitle] [nvarchar](50) NULL,
						[EventDate] [datetime] NOT NULL),
	                    PRIMARY KEY CLUSTERED ([VenueId],[EventId])
GO
CREATE UNIQUE INDEX [IX_Id] ON [dbo].[dim_Events] (VenueId, EventId)
GO

-- Create a venue dimension table in tenantanalytics database 
IF (OBJECT_ID('dim_Venues')) IS NOT NULL DROP TABLE dim_Venues
CREATE TABLE [dbo].[dim_Venues] 
						([VenueId] [int] NOT NULL,
						[VenueName] [nvarchar](50) NOT NULL,
						[VenueType] [char](30) NOT NULL,
						[VenueCapacity] [int] NOT NULL,
						[VenuepostalCode] [char](10) NULL,
						[VenueCountryCode] [char](3) NOT NULL,
	                    PRIMARY KEY CLUSTERED ([VenueId] ASC)
)
GO
CREATE UNIQUE INDEX [IX_VenueId] ON [dbo].[dim_Venues] (VenueId)
GO

-- Create a customer dimension table in tenantanalytics database 
IF (OBJECT_ID('dim_Customers')) IS NOT NULL DROP TABLE dim_Customers
CREATE TABLE [dbo].[dim_Customers] 
						([CustomerEmailId] [int] NOT NULL,
						[CustomerPostalCode] [char](10) NOT NULL,
						[CustomerCountryCode] [char](3) NOT NULL,
	                    PRIMARY KEY CLUSTERED ([CustomerEmailId] ASC)
)
GO
CREATE UNIQUE INDEX [IX_Customers_Email] ON [dbo].[dim_Customers] (CustomerEmailId)
GO

--Create a date dimension table
IF (OBJECT_ID('dim_Dates')) IS NOT NULL DROP TABLE dim_Dates
CREATE TABLE [dbo].[dim_Dates](
	[PurchaseDateID] [int] NULL,
	[DateValue] [date] NULL,
	[DateYear] [int] NULL,
	[DateMonth] [int] NULL,
	[DateDay] [int] NULL,
	[DateDayOfYear] [int] NULL,
	[DateWeekday] [int] NULL,
	[DateWeek] [int] NULL,
	[DateQuarter] [int] NULL,
	[DateMonthName] [nvarchar](30) NULL,
	[DateQuarterName] [nvarchar](31) NULL,
	[DateWeekdayName] [nvarchar](30) NULL,
	[MonthYear] [nvarchar](34) NULL,
	PRIMARY KEY CLUSTERED ([PurchaseDateID] ASC)
)
GO
CREATE UNIQUE INDEX [IX_PurchaseDateID] ON [dbo].[dim_Dates] (PurchaseDateID)
GO

-- Create a tickets fact table in tenantanalytics database 
IF (OBJECT_ID('fact_Tickets')) IS NOT NULL DROP TABLE fact_Tickets
CREATE TABLE [dbo].[fact_Tickets] 
						([TicketPurchaseId] [int] NOT NULL,
						[EventId] [int] NOT NULL,
						[CustomerEmailId] [int] NOT NULL,
						[VenueID] [int] NOT NULL,
						[PurchaseDateID ] [int] NOT NULL,
						[PurchaseTotal] [money] NOT NULL,
						[DaysToGo] [int] NOT NULL,
						[RowNumber] [int] NOT NULL,
						[SeatNumber] [int] NOT NULL,
	                    CONSTRAINT [FK_Tickets_PurchaseDateID] FOREIGN KEY ([PurchaseDateID]) REFERENCES [dim_Dates]([PurchaseDateID]),
	                    CONSTRAINT [FK_Tickets_EventId] FOREIGN KEY ([VenueId],[EventId]) REFERENCES [dim_Events]([VenueId], [EventId]),
	                    CONSTRAINT [FK_Tickets_VenueID] FOREIGN KEY ([VenueID]) REFERENCES [dim_Venues]([VenueID]),
	                    CONSTRAINT [FK_Tickets_CustomerEmailId] FOREIGN KEY ([CustomerEmailId]) REFERENCES [dim_Customers]([CustomerEmailId])
)
GO
CREATE CLUSTERED COLUMNSTORE INDEX cci_fact_Tickets
ON [fact_Tickets]
GO

CREATE PROCEDURE [dbo].[sp_ShredRawExtractedData]
AS

-- Variable to get the max timstamp of the source table
DECLARE @SourceLastTimestamp binary(8) = (SELECT MAX(RawTicketId) FROM  [dbo].[TicketsRawData])
DECLARE @SourceVELastTimestamp binary(8) = (SELECT MAX(RawVenueEventId) FROM  [dbo].[EventsRawData])

-- Merge purchase date from raw data to the dimension date table
MERGE INTO [dbo].[dim_dates] AS [target]
USING (SELECT DISTINCT PurchaseDateID = cast(replace(cast( convert(date, PurchaseDate) as varchar(25)),'-','')as int)
						,DateValue = convert(date, PurchaseDate)
						,DateYear = DATEPART(year,  PurchaseDate) 
						,DateMonth = DATEPART(month, PurchaseDate)  
						,DateDay = DATEPART(day,  PurchaseDate)  
						,DateDayOfYear = DATEPART(dayofyear,  PurchaseDate)  
						,DateWeekday = DATEPART(weekday,  PurchaseDate)
						,DateWeek = DATEPART(week,  PurchaseDate)
						,DateQuarter = DATEPART(quarter,  PurchaseDate)						
						,DateMonthName = DATENAME(month,  PurchaseDate)						
						,DateQuarterName = 'Q'+DATENAME(quarter,  PurchaseDate)						
						,DateWeekdayName = DATENAME(weekday,  PurchaseDate)
						,MonthYear = LEFT(DATENAME(month,  PurchaseDate),3)+'-'+DATENAME(year,  PurchaseDate)  
	   FROM [dbo].[TicketsRawData] WHERE RawTicketId <= @SourceLastTimestamp)
AS source(PurchaseDateID, DateValue, DateYear, DateMonth, DateDay, DateDayOfYear, DateWeekday, DateWeek, DateQuarter, DateMonthName, DateQuarterName, DateWeekdayName, MonthYear) 
ON ([target].PurchaseDateID = source.PurchaseDateID)
WHEN MATCHED THEN
UPDATE SET PurchaseDateID= source.PurchaseDateID, 
		   DateValue = source.DateValue, 
		   DateYear = source.DateYear,
		   DateMonth = source.DateMonth,
		   DateDay = source.DateDay,															
		   DateDayOfYear = source.DateDayOfYear,
		   DateWeekday = source.DateWeekday, 
		   DateWeek = source.DateWeek,
		   DateQuarter = source. DateQuarter,
		   DateMonthName = source. DateMonthName,
		   DateQuarterName = source. DateQuarterName,
		   DateWeekdayName = source. DateWeekdayName,
		   MonthYear = source.MonthYear
WHEN NOT MATCHED BY TARGET THEN
		   INSERT(PurchaseDateID, DateValue, DateYear, DateMonth, DateDay, DateDayOfYear, DateWeekday, DateWeek, DateQuarter, DateMonthName, DateQuarterName, DateWeekdayName, MonthYear)
		   VALUES(source.PurchaseDateID, source.DateValue, source.DateYear, source.DateMonth, source.DateDay, source.DateDayOfYear, source.DateWeekday, source.DateWeek, source.DateQuarter, source.DateMonthName, source.DateQuarterName, source.DateWeekdayName, source.MonthYear);


-- Merge customers from the raw data to the dimension table
MERGE INTO [dbo].[dim_Customers] AS [target]
USING (SELECT DISTINCT CustomerEmailId, CustomerPostalCode, CustomerCountryCode FROM [dbo].[TicketsRawData] WHERE RawTicketId <= @SourceLastTimestamp)
AS source (CustomerEmailId, CustomerPostalCode, CustomerCountryCode) 
ON ([target].CustomerEmailId = source.CustomerEmailId)
WHEN MATCHED THEN
UPDATE SET CustomerEmailId = source.CustomerEmailId, 
		   CustomerPostalCode = source.CustomerPostalCode, 
		   CustomerCountryCode = source.CustomerCountryCode
WHEN NOT MATCHED BY TARGET THEN
		   INSERT(CustomerEmailId, CustomerPostalCode, CustomerCountryCode)
		   VALUES(source.CustomerEmailId, source.CustomerPostalCode, source.CustomerCountryCode);

--dim_Events populate
MERGE INTO [dbo].[dim_Events] AS [target]
USING (SELECT [VenueId] [int], [EventId], [EventName], [EventSubtitle], [EventDate] 
       FROM [dbo].[EventsRawData] VE WHERE RawVenueEventId <= @SourceVELastTimestamp)
AS source (VenueId, EventId, EventName, EventSubtitle, EventDate) 
ON ([target].EventId = source.EventId AND [target].VenueId = source.VenueId)
WHEN MATCHED THEN
UPDATE SET VenueId = source.VenueId, 
		   EventId = source.EventId, 
		   EventName = source.EventName, 
		   EventSubtitle=source.EventSubtitle, 
		   EventDate=source.EventDate
WHEN NOT MATCHED BY TARGET THEN
		   INSERT(VenueId, EventId, EventName, EventSubtitle, EventDate)
		   VALUES(source.VenueId, source.EventId, source.EventName, source.EventSubtitle, source.EventDate);

-- dim_Venues populate
MERGE INTO [dbo].[dim_Venues] AS [target]
USING (SELECT DISTINCT [VenueId], [VenueName], [VenueType], [VenueCapacity], [VenuePostalCode], [VenueCountryCode] 
	   FROM [dbo].[EventsRawData] VE WHERE RawVenueEventId <= @SourceVELastTimestamp)
AS source (VenueId, VenueName, VenueType, VenueCapacity, VenuePostalCode, VenueCountryCode) 
ON [target].VenueId = source.VenueId
WHEN MATCHED THEN
UPDATE SET VenueId = source.VenueId, 
		   VenueName = source.VenueName, 
		   VenueType = source.VenueType, 
		   VenueCapacity = source. VenueCapacity,
		   VenuePostalCode=source.VenuePostalCode, 
		   VenueCountryCode= source.VenueCountryCode
WHEN NOT MATCHED BY TARGET THEN
		   INSERT(VenueId, VenueName, VenueType, VenueCapacity, VenuePostalCode, VenueCountryCode)
		   VALUES(source.VenueId, source.VenueName, source.VenueType, source.VenueCapacity, VenuePostalCode, source.VenueCountryCode);
		   
-- Merge tickets from raw data to the fact table
MERGE INTO [dbo].[fact_Tickets] AS [target]
USING (SELECT DISTINCT T.TicketPurchaseId
						,T.EventId
						,T.CustomerEmailId	
						,T.VenueId
						,PurchaseDateId = cast(replace(cast(convert(date, T.PurchaseDate) as varchar(25)),'-','')as int)
						,T.PurchaseTotal			
						,DaysToGo =  DATEDIFF(d, CAST(T.PurchaseDate AS DATE), CAST(E.EventDate AS DATE))
						,T.RowNumber
						,T.SeatNumber
	   FROM [dbo].[TicketsRawData] T 
	   INNER JOIN [dbo].[dim_Events] E on T.VenueId = E.VenueId AND T.EventId = E.EventId
	   WHERE T.RawTicketId <= @SourceLastTimestamp)
AS source(TicketPurchaseId, EventId, CustomerEmailId, VenueID, PurchaseDateId, PurchaseTotal, DaysToGo,  RowNumber, SeatNumber) 
ON ([target].TicketPurchaseId = source.TicketPurchaseId AND [target].RowNumber = source.RowNumber AND 
    [target].SeatNumber = source.SeatNumber AND [target].VenueId = source.VenueId)
WHEN MATCHED THEN
UPDATE SET TicketPurchaseId= source.TicketPurchaseId, 
		   EventId = source. PurchaseTotal,
		   CustomerEmailId = source.CustomerEmailId,
		   VenueId = source.VenueId,
		   PurchaseDateId = source.PurchaseDateId, 
		   PurchaseTotal = source.PurchaseTotal,	
		   DaysToGo = source.DaysToGo, 
		   RowNumber = source.RowNumber,
		   SeatNumber = source. SeatNumber
WHEN NOT MATCHED BY TARGET THEN
		   INSERT(TicketPurchaseId, EventId, CustomerEmailId, VenueId, PurchaseDateId, PurchaseTotal,  DaysToGo, RowNumber, SeatNumber)
		   VALUES(source.TicketPurchaseId, source.EventId, source.CustomerEmailId, source.VenueId, source.PurchaseDateId, source.PurchaseTotal, source.DaysToGo, source.RowNumber, source.SeatNumber);



--Delete the rows in the source table already shredded
DELETE FROM TicketsRawData
WHERE RawTicketId <= @SourceLastTimestamp


DELETE FROM [dbo].[EventsRawData]
WHERE RawVenueEventId <= @SourceVELastTimestamp
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
