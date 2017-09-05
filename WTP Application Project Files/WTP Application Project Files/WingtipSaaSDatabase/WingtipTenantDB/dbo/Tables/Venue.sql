CREATE TABLE [dbo].[Venue] (
    [VenueId]        INT            NOT NULL,
    [VenueName]      NVARCHAR (50)  NOT NULL,
  	[VenueType]      NVARCHAR(30)   NOT NULL,
    [AdminEmail]     NVARCHAR(128)  NOT NULL, 
    [AdminPassword]  NVARCHAR(30)   NULL, 
	[PostalCode]     NVARCHAR(20)   NULL, 
	[CountryCode]    CHAR(3)        NOT NULL,
    [RowVersion]     ROWVERSION     NOT NULL,
    [Lock]           CHAR           NOT NULL DEFAULT 'X', 
    CONSTRAINT [FK_Venues_Countries] FOREIGN KEY ([CountryCode]) REFERENCES [Countries]([CountryCode]), 
    CONSTRAINT [FK_Venues_VenueTypes] FOREIGN KEY ([VenueType]) REFERENCES [VenueTypes]([VenueType]), 
    CONSTRAINT [CK_Venue_Singleton] CHECK (Lock = 'X'), 
    CONSTRAINT [PK_Venue] PRIMARY KEY ([Lock])
);

