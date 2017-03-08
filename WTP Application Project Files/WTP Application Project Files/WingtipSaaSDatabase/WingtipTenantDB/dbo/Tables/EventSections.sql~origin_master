CREATE TABLE [dbo].[EventSections] (
    [EventId]           INT   NOT NULL,
    [SectionId]         INT   NOT NULL,
    [Price]             MONEY NOT NULL,
    PRIMARY KEY CLUSTERED ([EventId], [SectionId] ASC), 
    CONSTRAINT [FK_EventSections_Events] FOREIGN KEY ([EventId]) REFERENCES [Events]([EventId]), 
    CONSTRAINT [FK_EventSections_Sections] FOREIGN KEY ([SectionId]) REFERENCES [Sections]([SectionId])
);

