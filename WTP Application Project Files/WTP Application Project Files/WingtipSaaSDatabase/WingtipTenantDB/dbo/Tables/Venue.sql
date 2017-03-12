CREATE TABLE [dbo].[Venue] (
    [VenueName]      NVARCHAR (50)  NOT NULL,
  	[VenueType]      CHAR(30)      NOT NULL,
    [AdminEmail]     VARCHAR(50)     NOT NULL, 
    [AdminPassword]  NCHAR(30)     NULL, 
	[PostalCode]     CHAR(10)      NULL, 
	[CountryCode]    CHAR(3)       NOT NULL,
    [Lock]           CHAR NOT NULL DEFAULT 'X', 
    CONSTRAINT [FK_Venues_Countries] FOREIGN KEY ([CountryCode]) REFERENCES [Countries]([CountryCode]), 
    CONSTRAINT [FK_Venues_VenueTypes] FOREIGN KEY ([VenueType]) REFERENCES [VenueTypes]([VenueType]), 
    CONSTRAINT [CK_Venue_Singleton] CHECK (Lock = 'X'), 
    CONSTRAINT [PK_Venue] PRIMARY KEY ([Lock])
);

