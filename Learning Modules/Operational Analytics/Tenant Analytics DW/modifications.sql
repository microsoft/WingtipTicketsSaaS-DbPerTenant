-- Changes required for each tenant database for the new ADF tutorial

-- Created new views 
CREATE VIEW [dbo].[rawVenues]
	AS 	SELECT  v.VenueId, v.VenueName, v.VenueType,v.PostalCode as VenuePostalCode,  CountryCode AS VenueCountryCode,
	            (SELECT SUM (SeatRows * SeatsPerRow) FROM [dbo].[Sections]) AS VenueCapacity,
	            v.RowVersion AS VenueRowVersion
	FROM        [dbo].[Venue] as v
GO


CREATE VIEW [dbo].[rawEvents]
	AS 	SELECT  (SELECT TOP 1 VenueId FROM Venues) AS VenueId, e.EventId, e.EventName, e.Subtitle AS EventSubtitle, e.Date AS EventDate,
	            e.RowVersion AS EventRowVersion
	FROM        [dbo].[Events] as e
GO

CREATE VIEW [dbo].[rawCustomers]
AS 	SELECT  (SELECT TOP 1 VenueId FROM Venues) AS VenueId, Convert(int, HASHBYTES(''md5'',c.Email)) AS CustomerEmailId, 
            c.PostalCode AS CustomerPostalCode, c.CountryCode AS CustomerCountryCode,
	            c.RowVersion AS CustomerRowVersion
FROM        [dbo].[Customers]  as c
GO 

CREATE VIEW [dbo].[rawTickets] AS
    SELECT      v.VenueId, Convert(int, HASHBYTES(''md5'',c.Email)) AS CustomerEmailId,
	            tp.TicketPurchaseId, tp.PurchaseDate, tp.PurchaseTotal, tp.RowVersion AS TicketPurchaseRowVersion,
	            e.EventId, t.RowNumber, t.SeatNumber 
	FROM        [dbo].[TicketPurchases] AS tp 
	INNER JOIN [dbo].[Tickets] AS t ON t.TicketPurchaseId = tp.TicketPurchaseId 
	INNER JOIN [dbo].[Events] AS e ON t.EventId = e.EventId 
	INNER JOIN [dbo].[Customers] AS c ON tp.CustomerId = c.CustomerId
	INNER join [dbo].[Venue] as v on 1=1
GO

-- Added tracker table in each tenant 
CREATE TABLE [dbo].[CopyTracker](
	[Id] [bigint] IDENTITY(1,1) NOT NULL,
	[TableName] [nvarchar](max) NOT NULL,
	[TrackerKey] [nvarchar](max) NOT NULL,
	[LastCopiedValue] [varbinary](8) NOT NULL,
	[RunId] [nvarchar](max) NULL,
	[RunTimeStamp] [datetime] NULL
)
GO

--
CREATE PROCEDURE [dbo].[SaveLastCopiedRowVersion]
(
    -- Add the parameters for the stored procedure here
    @tableName nvarchar(50),
    @trackerKey nvarchar(50),
    @lastCopiedValue varchar(25),
    @runId nvarchar(max),
    @runTimeStamp datetime
)
AS
BEGIN
    -- SET NOCOUNT ON added to prevent extra result sets from
    -- interfering with SELECT statements.
    SET NOCOUNT ON
	
	Declare @copiedValue VARBINARY(8)

	SELECT @copiedValue = CONVERT(VARBINARY(8), @lastCopiedValue, 1)

	INSERT INTO 
		[dbo].[CopyTracker]([TableName], [TrackerKey], [LastCopiedValue], [RunId], [RunTimeStamp]) 
	VALUES
		(@tableName, @trackerKey, @copiedValue, @runId, @runTimeStamp)
END
GO
