    CREATE VIEW [dbo].[VenueTickets] AS 
    SELECT (SELECT TOP 1 VenueId FROM Venues) AS VenueId, TicketId, RowNumber, SeatNumber, EventId, SectionId, TicketPurchaseId FROM [Tickets]