CREATE TABLE [dbo].[Venues] (
    [VenueId]        INT            NOT NULL,
    [VenueName]      NVARCHAR (50)  NOT NULL,
  	[VenueType]      NVARCHAR(30)   NOT NULL,
    [AdminEmail]     NVARCHAR(128)  NOT NULL, 
    [AdminPassword]  NVARCHAR(30)   NULL, 
	[PostalCode]     NVARCHAR(20)   NULL, 
	[CountryCode]    CHAR(3)        NOT NULL,
    [RowVersion]     ROWVERSION     NOT NULL, 
    CONSTRAINT [FK_Venues_Countries] FOREIGN KEY ([CountryCode]) REFERENCES [Countries]([CountryCode]), 
    CONSTRAINT [FK_Venues_VenueTypes] FOREIGN KEY ([VenueType]) REFERENCES [VenueTypes]([VenueType]), 
    CONSTRAINT [PK_Venues] PRIMARY KEY ([VenueId])
);
GO

CREATE INDEX IX_Venues_VenueType ON [dbo].[Venues] ([VenueType])
GO

CREATE INDEX IX_Venues_CountryCode ON [dbo].[Venues] ([CountryCode])
GO
