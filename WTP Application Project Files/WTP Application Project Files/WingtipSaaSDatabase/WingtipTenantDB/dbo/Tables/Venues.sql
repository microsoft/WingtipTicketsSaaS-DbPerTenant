CREATE TABLE [dbo].[Venues] (
    [VenueName]      NVARCHAR (50)  NOT NULL,
  	[VenueType]      CHAR(30)      NOT NULL,
    [AdminEmail]     NCHAR(30)     NOT NULL, 
    [AdminPassword]  NCHAR(30)     NULL, 
	[PostalCode]     CHAR(10)      NULL, 
	[CountryCode]    CHAR(3)       NOT NULL,
    CONSTRAINT [FK_Venues_Countries] FOREIGN KEY ([CountryCode]) REFERENCES [Countries]([CountryCode]), 
    CONSTRAINT [FK_Venues_VenueTypes] FOREIGN KEY ([VenueType]) REFERENCES [VenueTypes]([VenueType])
);

