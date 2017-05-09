    CREATE VIEW [dbo].[TicketFacts] AS
    SELECT  v.VenueId, v.VenueName, v.VenueType,v.VenuePostalCode, v.VenueCapacity,
            tp.TicketPurchaseId, tp.PurchaseDate, tp.PurchaseTotal,
            t.RowNumber, t.SeatNumber, 
            c.CustomerId, c.PostalCode AS CustomerPostalCode, c.CountryCode, 
            e.EventId, e.EventName, e.Subtitle AS EventSubtitle, e.Date AS EventDate
    FROM    (
              SELECT  (SELECT TOP 1 VenueId FROM [dbo].[Venues]) AS VenueId,
                      VenueName, VenueType, PostalCode AS VenuePostalCode,
                      (SELECT SUM ([SeatRows]*[SeatsPerRow]) FROM [dbo].[Sections]) AS VenueCapacity, 
                      1 AS X FROM Venue
            ) as v
            INNER JOIN [dbo].[TicketPurchases] AS tp ON v.X = 1
            INNER JOIN [dbo].[Tickets] AS t ON t.TicketPurchaseId = tp.TicketPurchaseId
            INNER JOIN [dbo].[Events] AS e ON t.EventId = e.EventId
            INNER JOIN [dbo].[Customers] AS c ON tp.CustomerId = c.CustomerId