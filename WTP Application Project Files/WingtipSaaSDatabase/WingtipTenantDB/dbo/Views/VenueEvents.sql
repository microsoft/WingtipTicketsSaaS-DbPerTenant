    CREATE VIEW [dbo].[VenueEvents] AS
    SELECT (SELECT TOP 1 VenueId FROM Venues) AS VenueId, EventId, EventName, Subtitle, Date FROM [events]