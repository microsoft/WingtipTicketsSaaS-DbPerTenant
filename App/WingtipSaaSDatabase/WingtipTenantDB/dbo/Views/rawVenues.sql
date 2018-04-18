CREATE VIEW [dbo].[rawVenues]
	AS 	SELECT  v.VenueId, v.VenueName, v.VenueType,v.PostalCode as VenuePostalCode,  CountryCode AS VenueCountryCode,
	            (SELECT SUM (SeatRows * SeatsPerRow) FROM [dbo].[Sections]) AS VenueCapacity,
	            v.RowVersion AS VenueRowVersion
	FROM        [dbo].[Venue] as v
GO
