CREATE VIEW [dbo].[EventFacts]
	AS 	SELECT  v.VenueId, v.VenueName, v.VenueType,v.PostalCode as VenuePostalCode,  CountryCode AS VenueCountryCode,
	            (SELECT SUM (SeatRows * SeatsPerRow) FROM [dbo].[Sections]) AS VenueCapacity,
	            v.RowVersion AS VenueRowVersion,
	            e.EventId, e.EventName, e.Subtitle AS EventSubtitle, e.Date AS EventDate,
	            e.RowVersion AS EventRowVersion
	FROM        [dbo].[Venue] as v
	INNER JOIN [dbo].[Events] as e on 1=1