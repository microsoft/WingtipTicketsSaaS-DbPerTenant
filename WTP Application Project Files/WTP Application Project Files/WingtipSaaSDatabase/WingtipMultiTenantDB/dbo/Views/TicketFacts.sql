CREATE VIEW [dbo].[TicketFacts] AS
SELECT      v.VenueId, v.VenueName, v.VenueType,v.PostalCode as VenuePostalCode,  
            (SELECT SUM (SeatRows * SeatsPerRow) FROM [dbo].[Sections] WHERE VenueId = v.VenueId) AS VenueCapacity,
            tp.TicketPurchaseId, tp.PurchaseDate, tp.PurchaseTotal,
            t.RowNumber, t.SeatNumber, 
            c.CustomerId, c.PostalCode AS CustomerPostalCode, c.CountryCode, Convert(int, HASHBYTES('md5',c.Email)) AS CustomerEmailId, 
            e.EventId, e.EventName, e.Subtitle AS EventSubtitle, e.Date AS EventDate
    FROM    [dbo].[Venues] as v
            INNER JOIN [dbo].[TicketPurchases] AS tp ON tp.VenueId = v.VenueId
            INNER JOIN [dbo].[Tickets] AS t ON t.TicketPurchaseId = tp.TicketPurchaseId AND t.VenueId = v.VenueId
            INNER JOIN [dbo].[Events] AS e ON t.EventId = e.EventId AND e.VenueId = v.VenueId
            INNER JOIN [dbo].[Customers] AS c ON tp.CustomerId = c.CustomerId AND c.VenueId = v.VenueId
