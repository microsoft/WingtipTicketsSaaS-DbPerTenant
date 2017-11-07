    CREATE VIEW [dbo].[Venues] AS
    SELECT VenueId, VenueName, VenueType, AdminEmail, PostalCode, CountryCode, @@ServerName as Server, DB_NAME() AS [DatabaseName] FROM [Venue]