CREATE TABLE [dbo].[TicketPurchases]
(
    [TicketPurchaseId]  INT         NOT NULL IDENTITY (1,1), 
    [PurchaseDate]      DATETIME    NOT NULL, 
    [PurchaseTotal]     MONEY       NOT NULL,
    [CustomerId]        INT         NOT NULL,
    [RowVersion]        ROWVERSION, 
    PRIMARY KEY CLUSTERED ([TicketPurchaseId] ASC), 
    CONSTRAINT [FK_TicketPurchases_Customers] FOREIGN KEY ([CustomerId]) REFERENCES [Customers]([CustomerId])
)

GO


CREATE INDEX [IX_TicketPurchases_CustomerId] ON [dbo].[TicketPurchases] (CustomerId)
