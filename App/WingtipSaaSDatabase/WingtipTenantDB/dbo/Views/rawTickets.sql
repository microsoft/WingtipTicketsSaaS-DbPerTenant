CREATE VIEW [dbo].[rawTickets] AS
    SELECT      v.VenueId, Convert(int, HASHBYTES('md5',c.Email)) AS CustomerEmailId,
	            tp.TicketPurchaseId, tp.PurchaseDate, tp.PurchaseTotal, tp.RowVersion AS TicketPurchaseRowVersion,
	            e.EventId, t.RowNumber, t.SeatNumber 
	FROM        [dbo].[TicketPurchases] AS tp 
	INNER JOIN [dbo].[Tickets] AS t ON t.TicketPurchaseId = tp.TicketPurchaseId 
	INNER JOIN [dbo].[Events] AS e ON t.EventId = e.EventId 
	INNER JOIN [dbo].[Customers] AS c ON tp.CustomerId = c.CustomerId
	INNER join [dbo].[Venue] as v on 1=1
GO