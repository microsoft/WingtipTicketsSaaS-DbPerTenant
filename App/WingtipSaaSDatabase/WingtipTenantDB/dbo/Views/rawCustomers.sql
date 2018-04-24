CREATE VIEW [dbo].[rawCustomers]
AS 	SELECT  (SELECT TOP 1 VenueId FROM Venues) AS VenueId, Convert(int, HASHBYTES('md5',c.Email)) AS CustomerEmailId, 
            c.PostalCode AS CustomerPostalCode, c.CountryCode AS CustomerCountryCode,
	            c.RowVersion AS CustomerRowVersion
FROM        [dbo].[Customers]  as c
GO 
