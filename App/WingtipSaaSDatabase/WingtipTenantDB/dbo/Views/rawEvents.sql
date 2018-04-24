CREATE VIEW [dbo].[rawEvents]
	AS 	SELECT  (SELECT TOP 1 VenueId FROM Venues) AS VenueId, e.EventId, e.EventName, e.Subtitle AS EventSubtitle, e.Date AS EventDate,
	            e.RowVersion AS EventRowVersion
	FROM        [dbo].[Events] as e
GO