CREATE TABLE [dbo].[Sections] (
    [SectionId]         INT           IDENTITY (1, 1) NOT NULL,
    [SectionName]       NVARCHAR (30) NOT NULL,
    [SeatRows]          SMALLINT NOT NULL DEFAULT 20, 
    [SeatsPerRow]       SMALLINT NOT NULL DEFAULT 30,
    [StandardPrice]     MONEY NOT NULL DEFAULT 10, 
    [RowVersion] ROWVERSION NOT NULL, 
    PRIMARY KEY CLUSTERED ([SectionId] ASC), 
    CONSTRAINT [CK_Sections_SeatRows] CHECK (SeatRows <= 1000 and SeatRows > 0),
    CONSTRAINT [CK_Sections_SeatsPerRow] CHECK (SeatsPerRow <= 1000 and SeatsPerRow > 0),
    CONSTRAINT [CK_Sections_StandardPrice] CHECK (StandardPrice <= 100000)
);

GO

