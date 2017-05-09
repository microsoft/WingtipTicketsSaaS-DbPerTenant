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
FROM	dbo.VenuesGlobal

GO

-- What are the most popular venue types?
SELECT VenueType, 
	   Count(TicketId) AS PurchasedTicketCount
FROM   dbo.VenuesGlobal 
	   INNER JOIN dbo.VenueTickets ON VenuesGlobal.VenueId = VenueTickets.VenueId
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
				INNER JOIN VenuesGlobal ON VenueEvents.VenueId = VenuesGlobal.VenueId
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
		INNER JOIN VenuesGlobal ON VenueEvents.VenueId = VenuesGlobal.VenueId
GROUP	BY VenueName, Subtitle, EventName, (CAST(VenueEvents.Date AS DATE))
ORDER	BY SUM(PurchaseTotal) DESC

GO