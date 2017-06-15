-- *******************************************************
-- SETUP Adhoc Analytics Infrastructure
-- *******************************************************

-- Create encryption key that will encrypt database logins
CREATE MASTER KEY;
GO

-- Create login credential for catalog database
CREATE DATABASE SCOPED CREDENTIAL [AdhocQueryDBCred]
WITH IDENTITY = N'developer', SECRET = N'P@ssword1';
GO

-- Add catalog database as external data source using credential created above
-- **NOTE:** MODIFY <USER> VARIABLE BELOW
CREATE EXTERNAL DATA SOURCE [WtpTenantDBs]
WITH
(
	TYPE = SHARD_MAP_MANAGER,
	LOCATION = N'catalog-<USER>.database.windows.net', -- << MODIFY <USER> variable with your user id from Wingtip deployment
	DATABASE_NAME = 'tenantcatalog',
	SHARD_MAP_NAME = 'tenantcatalog',
	CREDENTIAL = [AdhocQueryDBCred]
);
GO

-- Add tenant tables that will be used for querying data across all tenants

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER OFF;
GO

CREATE EXTERNAL TABLE [dbo].[VenueEvents]
(
    [VenueId] INT NOT NULL,
    [EventId] INT NOT NULL,
    [EventName] NVARCHAR (50) NOT NULL,
    [Subtitle] NVARCHAR (50) NULL,
    [Date] DATETIME NOT NULL
)
WITH
(
    DATA_SOURCE = [WtpTenantDBs],
    DISTRIBUTION = ROUND_ROBIN
);
GO

SET ANSI_NULLS, QUOTED_IDENTIFIER ON;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER OFF;
GO

CREATE EXTERNAL TABLE [dbo].[VenueTicketPurchases]
(
    [VenueId] INT NOT NULL,
    [TicketPurchaseId] INT NOT NULL,
    [PurchaseDate] DATETIME NOT NULL,
    [PurchaseTotal] MONEY NOT NULL,
    [CustomerId] INT NOT NULL
)
WITH
(
	DATA_SOURCE = [WtpTenantDBs],
	DISTRIBUTION = ROUND_ROBIN
);
GO

SET ANSI_NULLS, QUOTED_IDENTIFIER ON;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER OFF;
GO

CREATE EXTERNAL TABLE [dbo].[VenueTickets]
(
    [VenueId] INT NOT NULL,
    [TicketId] INT NOT NULL,
    [RowNumber] INT NOT NULL,
    [SeatNumber] INT NOT NULL,
    [EventId] INT NOT NULL,
    [SectionId] INT NOT NULL,
    [TicketPurchaseId] INT NOT NULL
)
WITH
(
	DATA_SOURCE = [WtpTenantDBs],
	DISTRIBUTION = ROUND_ROBIN
);
GO
    
SET ANSI_NULLS, QUOTED_IDENTIFIER ON;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER OFF;
GO
    
CREATE EXTERNAL TABLE [dbo].[Venues]
(
    [VenueId] INT NOT NULL,
    [VenueName] NVARCHAR (50) NOT NULL,
    [VenueType] CHAR (30) NOT NULL,
    [AdminEmail] NCHAR (30) NOT NULL,
    [PostalCode] CHAR (10) NULL,
    [CountryCode] CHAR (3) NOT NULL,
    [Server] NVARCHAR(128) NOT NULL,
    [DatabaseName] NVARCHAR(128) NOT NULL
)
WITH
(
	DATA_SOURCE = [WtpTenantDBs],
	DISTRIBUTION = ROUND_ROBIN
);
GO

CREATE TABLE [dbo].[VenueTypes]
(
    [VenueType] CHAR(30) NOT NULL,
    [VenueTypeName] NCHAR(30) NOT NULL,  
    [EventTypeName] NVARCHAR(30) NOT NULL, 
    [EventTypeShortName] NVARCHAR(20) NOT NULL,
    [EventTypeShortNamePlural] NVARCHAR(20) NOT NULL,
    [Language] CHAR(8) NOT NULL,
    PRIMARY KEY CLUSTERED ([VenueType] ASC)
)
GO

-- Create local venuetypes table that will store the types of venues available on the Wingtips tickets platform

CREATE UNIQUE INDEX IX_VENUETYPES_VENUETYPE ON [dbo].[VenueTypes] ([VenueType])
GO

CREATE UNIQUE INDEX IX_VENUETYPES_VENUETYPENAME_LANGUAGE ON [dbo].[VenueTypes] ([VenueTypeName], [Language])
GO

INSERT INTO [dbo].[VenueTypes]
    ([VenueType],[VenueTypeName],[EventTypeName],[EventTypeShortName],[EventTypeShortNamePlural],[Language])
VALUES
    ('multipurpose','Multi-Purpose','Event', 'Event','Events','en-us'),
    ('classicalmusic','Classical Music ','Classical Concert','Concert','Concerts','en-us'),
    ('jazz','Jazz','Jazz Session','Session','Sessions','en-us'),
    ('judo','Judo','Judo Tournament','Tournament','Tournaments','en-us'),
    ('soccer','Soccer','Soccer Match', 'Match','Matches','en-us'),
    ('motorracing','Motor Racing','Car Race', 'Race','Races','en-us'),
    ('dance', 'Dance', 'Performance', 'Performance', 'Performances','en-us'),
    ('blues', 'Blues', 'Blues Session', 'Session','Sessions','en-us' ),
    ('rockmusic','Rock Music','Rock Concert','Concert', 'Concerts','en-us'),
    ('opera','Opera','Opera','Opera','Operas','en-us');      
GO

PRINT N'Update complete.';
GO

--- Verify that the external data source and tables exist in the adhoc analytics database
select * from sys.external_data_sources;
select * from sys.external_tables;
GO

-- *******************************************************
-- SAMPLE QUERIES
-- *******************************************************

-- Which venues are currently registered on the Wingtip platform?
SELECT	VenueName,
		VenueType
FROM	dbo.Venues

GO

-- What are the most popular venue types?
SELECT VenueType, 
	   Count(TicketId) AS PurchasedTicketCount
FROM   dbo.Venues 
	   INNER JOIN dbo.VenueTickets ON Venues.VenueId = VenueTickets.VenueId
GROUP  BY VenueType
ORDER  BY PurchasedTicketCount DESC

GO

-- On which day were the most tickets sold?
SELECT	CAST(PurchaseDate AS DATE) AS TicketPurchaseDate,
		Count(TicketId) AS TicketCount
FROM	VenueTicketPurchases
		INNER JOIN VenueTickets ON (VenueTickets.TicketPurchaseId = VenueTicketPurchases.TicketPurchaseId AND VenueTickets.VenueId = VenueTicketPurchases.VenueId)
GROUP	BY (CAST(PurchaseDate AS DATE))
ORDER	BY TicketCount DESC, TicketPurchaseDate ASC

GO

-- Which event had the highest revenue at each venue?
EXEC sp_execute_remote
	N'WtpTenantDBs',
	N'SELECT	TOP (1)
				VenueName,
				EventName,
				Subtitle AS Performers,
				COUNT(TicketId) AS TicketsSold,
				CONVERT(VARCHAR(30), SUM(PurchaseTotal), 1) AS PurchaseTotal
	  FROM		VenueEvents
				INNER JOIN VenueTickets ON VenueTickets.EventId = VenueEvents.EventId
				INNER JOIN VenueTicketPurchases ON VenueTicketPurchases.TicketPurchaseId = VenueTickets.TicketPurchaseId
				INNER JOIN Venues ON VenueEvents.VenueId = Venues.VenueId
	  GROUP		BY VenueName, EventName, Subtitle
	  ORDER		BY PurchaseTotal DESC'

GO

-- What are the top 10 grossing events across all venues on the WTP platform
SELECT	TOP (10)
		VenueName,
		EventName,
		Subtitle AS EventPerformers,
		CAST(VenueEvents.Date AS DATE) AS EventDate,
		COUNT(TicketId) AS TicketPurchaseCount,
		CONVERT(VARCHAR(30), SUM(PurchaseTotal), 1) AS EventRevenue
FROM	VenueEvents
		INNER JOIN VenueTickets ON (VenueTickets.EventId = VenueEvents.EventId AND VenueTickets.VenueId = VenueEvents.VenueId)
		INNER JOIN VenueTicketPurchases ON (VenueTicketPurchases.TicketPurchaseId = VenueTickets.TicketPurchaseId AND VenueTicketPurchases.VenueId = VenueEvents.VenueId)
		INNER JOIN Venues ON VenueEvents.VenueId = Venues.VenueId
GROUP	BY VenueName, Subtitle, EventName, (CAST(VenueEvents.Date AS DATE))
ORDER	BY SUM(PurchaseTotal) DESC

GO