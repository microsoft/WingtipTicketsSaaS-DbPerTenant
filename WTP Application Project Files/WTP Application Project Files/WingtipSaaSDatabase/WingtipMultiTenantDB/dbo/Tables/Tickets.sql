CREATE TABLE [dbo].[Tickets] (
    [VenueId]               INT NOT NULL,    
    [TicketId]              INT IDENTITY NOT NULL,
	[RowNumber]             INT NOT NULL,
    [SeatNumber]            INT NOT NULL, 
    [EventId]               INT NOT NULL,
    [SectionId]             INT NOT NULL,
    [TicketPurchaseId]      INT NOT NULL,
    PRIMARY KEY CLUSTERED ([VenueId], [TicketId] ASC),
    CONSTRAINT [FK_Tickets_TicketPurchases] FOREIGN KEY ([VenueId], [TicketPurchaseId]) REFERENCES [TicketPurchases]([VenueId], [TicketPurchaseId]) ON DELETE CASCADE, 
    CONSTRAINT [FK_Tickets_EventSections] FOREIGN KEY ([VenueId], [EventId], [SectionId]) REFERENCES [EventSections]([VenueId], [EventId],[SectionId])
);

GO

CREATE UNIQUE INDEX [IX_Tickets] ON [dbo].[Tickets] ([EventId], [SectionId], [RowNumber], [SeatNumber])
