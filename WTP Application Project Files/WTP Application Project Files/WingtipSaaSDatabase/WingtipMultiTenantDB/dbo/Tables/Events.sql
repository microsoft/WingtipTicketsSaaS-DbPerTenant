CREATE TABLE [dbo].[Events] (
    [VenueId]            INT           NOT NULL,
    [EventId]            INT IDENTITY  NOT NULL,
    [EventName]          NVARCHAR(50)  NOT NULL,
    [Subtitle]           NVARCHAR(50)  NULL,
    [Date]               DATETIME      NOT NULL,
    [RowVersion]         ROWVERSION    NOT NULL, 
    PRIMARY KEY CLUSTERED ([VenueId], [EventId] ASC),
    CONSTRAINT [FK_Events_Venues] FOREIGN KEY ([VenueId]) REFERENCES [Venues]([VenueId]) 
);

GO

