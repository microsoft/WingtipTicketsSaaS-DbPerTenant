--- Verify that the external data source and tables exist in the adhoc analytics database
select * from sys.external_data_sources;
select * from sys.external_tables;

GO

-- *******************************************************
-- SOME ADHOC QUERIES. Any others you would like to try?
-- *******************************************************

-- What venues are registered on the Wingtip platform right now?
SELECT	VenueName,
		VenueType
FROM	dbo.Venue

GO

-- What are the most popular venue types?
SELECT VenueType, 
	   Count(TicketPurchaseId) AS PurchasedTicketCount
FROM   dbo.Venue
	   INNER JOIN dbo.TicketPurchases ON TicketPurchaseId > 0
GROUP  BY VenueType
ORDER  BY PurchasedTicketCount DESC

GO

-- Which day had the most tickets sold?
SELECT CAST(PurchaseDate AS DATE) AS TicketPurchaseDate,
	   Count(TicketPurchaseId) AS TicketCount
FROM   TicketPurchases
GROUP  BY PurchaseDate
ORDER  BY TicketCount DESC, TicketPurchaseDate ASC

GO

-- What was the highest revenue event per each venue?
EXEC sp_execute_remote
	N'WtpTenantDBs',
	N'SELECT	TOP (1)
				VenueName,
				EventName,
				SUM(PurchaseTotal) AS PurchaseTotal
	  FROM		Venue
				INNER JOIN Events ON Events.EventId > 0
				INNER JOIN Tickets ON Tickets.EventId = Events.EventId
				INNER JOIN TicketPurchases ON TicketPurchases.TicketPurchaseId = Tickets.TicketPurchaseId
	  GROUP		BY VenueName, EventName
	'

GO

-- What are the top 10 grossing events across all venues on the WTP platform
		
--Create temp table to hold the highest revenue events from each venue
DROP TABLE IF EXISTS #tmpMaxRevenue
CREATE TABLE #tmpMaxRevenue (VenueName nvarchar(50), EventName nvarchar(50), PurchaseTotal money, ShardName nvarchar(200))
INSERT INTO #tmpMaxRevenue (VenueName, EventName, PurchaseTotal, ShardName)
EXEC sp_execute_remote  
    N'WtpTenantDBs',
	N'SELECT	TOP (10)
				(SELECT TOP (1) VenueName FROM Venue) AS VenueName,
				EventName,
				SUM(PurchaseTotal) AS PurchaseTotal
	  FROM		Events 
				INNER JOIN Tickets ON Tickets.EventId = Events.EventId
				INNER JOIN TicketPurchases ON TicketPurchases.TicketPurchaseId = Tickets.TicketPurchaseId
	  GROUP		BY EventName
	  ORDER		BY PurchaseTotal DESC' 
	  
-- Select highest grossing events. Reference event revenue temp table from above
SELECT	TOP (10)
		VenueName,
		EventName, 
		PurchaseTotal
FROM	#tmpMaxRevenue
GROUP	BY VenueName, PurchaseTotal, EventName
ORDER	BY PurchaseTotal DESC, EventName  

GO




 
