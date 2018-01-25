CREATE TABLE [dbo].[Tickets] (
    [TicketId]              INT         IDENTITY (1, 1) NOT NULL,
	[RowNumber]             INT         NOT NULL,
    [SeatNumber]            INT         NOT NULL, 
    [EventId]               INT         NOT NULL,
    [SectionId]             INT         NOT NULL,
    [TicketPurchaseId]      INT         NOT NULL,
    PRIMARY KEY CLUSTERED ([TicketId] ASC), 
    CONSTRAINT [FK_Tickets_TicketPurchases] FOREIGN KEY ([TicketPurchaseId]) REFERENCES [TicketPurchases]([TicketPurchaseId]) ON DELETE CASCADE, 
    CONSTRAINT [FK_Tickets_EventSections] FOREIGN KEY ([EventId], [SectionId]) REFERENCES [EventSections]([EventId],[SectionId])
);

GO

CREATE UNIQUE INDEX [IX_Tickets] ON [dbo].[Tickets] ([EventId], [SectionId], [RowNumber], [SeatNumber])
