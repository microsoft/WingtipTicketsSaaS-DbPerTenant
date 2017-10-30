CREATE TABLE [dbo].[Events] (
    [EventId]            INT           IDENTITY (1, 1) NOT NULL,
    [EventName]          NVARCHAR(50)  NOT NULL,
    [Subtitle]           NVARCHAR(50)   NULL,
    [Date]               DATETIME      NOT NULL,
    [RowVersion]         ROWVERSION,
    PRIMARY KEY CLUSTERED ([EventId] ASC), 
);

