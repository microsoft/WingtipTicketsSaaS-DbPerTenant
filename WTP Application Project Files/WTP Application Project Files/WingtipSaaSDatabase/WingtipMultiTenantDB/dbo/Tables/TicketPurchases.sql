CREATE TABLE [dbo].[TicketPurchases]
(
    [VenueId]           INT         NOT NULL,
    [TicketPurchaseId]  INT         NOT NULL IDENTITY, 
    [PurchaseDate]      DATETIME    NOT NULL, 
    [PurchaseTotal]     MONEY       NOT NULL,
    [CustomerId]        INT         NOT NULL,
    [RowVersion]        ROWVERSION  NOT NULL, 
    PRIMARY KEY CLUSTERED ([VenueId], [TicketPurchaseId] ASC), 
    CONSTRAINT [FK_TicketPurchases_Customers] FOREIGN KEY ([VenueId], [CustomerId]) REFERENCES [Customers]([VenueId], [CustomerId])
)

GO