CREATE VIEW [dbo].[EventsWithNoTickets]
    AS SELECT VenueId, EventId, EventName, Subtitle, Date from dbo.Events as e
    WHERE (SELECT Count(*) FROM dbo.Tickets AS t WHERE t.EventId=e.EventId and t.VenueId = e.VenueId) = 0
