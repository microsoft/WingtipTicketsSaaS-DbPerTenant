    CREATE VIEW [dbo].[VenueTicketPurchases] AS
    SELECT (SELECT TOP 1 VenueId FROM Venues) AS VenueId, TicketPurchaseId, PurchaseDate, PurchaseTotal, CustomerId FROM [TicketPurchases]