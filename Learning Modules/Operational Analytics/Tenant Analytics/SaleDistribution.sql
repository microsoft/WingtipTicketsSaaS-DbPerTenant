-- Percentage of events and corresponding percentage of tickets sold.
CREATE VIEW [dbo].[TicketSalesDistribution]
AS
SELECT DISTINCT V.VenueName
	  ,E.EventName
	  ,TotalTicketsSold = COUNT(*) OVER (Partition by EventName+VenueName)
	  ,PercentTicketsSold = cast(cast(COUNT(*) OVER (Partition by EventName+VenueName) as float)/cast(V.VenueCapacity as float)*100 as int)
FROM [dbo].[fact_Tickets] T
JOIN [dbo].[dim_Venues] V
ON V.VenueId = T. VenueId
JOIN [dbo].[dim_Events] E
ON E.EventId = T. EventId AND E.VenueId = T.VenueId
GO

-- Total sales versus sale day
CREATE VIEW [dbo].[TicketsSoldVersusSaleDay]
AS
SELECT VenueName
	  ,SaleDay = (60-DaysToGo)
      ,DailyTicketsSold = MAX(DailyTicketsSold)
FROM (
SELECT V.VenueName
	  ,DaysToGo = T.DaysToGo
      ,DailyTicketsSold = COUNT(*) OVER (partition by VenueName,T.DaysToGo)
FROM [dbo].[fact_Tickets] T
JOIN [dbo].[dim_Venues] V
ON V.VenueId = T. VenueId
JOIN [dbo].[dim_Events] E
ON E.EventId = T. EventId AND E.VenueId = T.VenueId
JOIN [dbo].[dim_Dates] D
ON  D.PurchaseDateID = T.PurchaseDateID
)A
GROUP BY VenueName
		,DaysToGo
GO

-- Cumulative Daily Sales for all venues
CREATE VIEW [dbo].[CumulativeDailySalesByEvent]
AS
SELECT VenueName
	  ,EventName
	  ,SaleDay = (60-DaysToGo)
      ,RunningTicketsSoldTotal = MAX(RunningTicketsSold)
	  ,Event = VenueName+'+'+EventName
FROM (
SELECT V.VenueName
	  ,E.EventName
	  ,DaysToGo = T.DaysToGo
      ,RunningTicketsSold = COUNT(*) OVER (Partition by EventName+VenueName Order by T.PurchaseDateID)
FROM [dbo].[fact_Tickets] T
JOIN [dbo].[dim_Venues] V
ON V.VenueId = T. VenueId
JOIN [dbo].[dim_Events] E
ON E.EventId = T. EventId AND E.VenueId = T.VenueId
UNION ALL
SELECT VenueName, EventName, DaysToGo = 60, RunningTicketsSold = 0
FROM [dbo].[dim_Venues] V
JOIN [dbo].[dim_Events] E
ON E.VenueId = V.VenueId

)A
GROUP BY VenueName
		,EventName
		,DaysToGo
GO

-- Total sales versus date
CREATE VIEW [dbo].[TotalSalesPerDay]
AS
SELECT VenueName
	  ,Date = DateValue
      ,DailyTicketsSold = MAX(DailyTicketsSold)
FROM (
SELECT V.VenueName
	  ,D.DateValue
      ,DailyTicketsSold = COUNT(*) OVER (partition by VenueName,D.DateValue)
FROM [dbo].[fact_Tickets] T
JOIN [dbo].[dim_Venues] V
ON V.VenueId = T. VenueId
JOIN [dbo].[dim_Events] E
ON E.EventId = T. EventId AND E.VenueId = T.VenueId
JOIN [dbo].[dim_Dates] D
ON  D.PurchaseDateID = T.PurchaseDateID
)A
GROUP BY VenueName
		,DateValue
GO