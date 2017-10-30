-- Fabrikam Jazz Club Initialization
--
-- All existing data will be deleted (excluding reference tables)
--
-----------------------------------------------------------------

-- Delete all current data
DELETE FROM [dbo].[Tickets]
DELETE FROM [dbo].[TicketPurchases]
DELETE FROM [dbo].[Customers]
DELETE FROM [dbo].[EventSections]
DELETE FROM [dbo].[Events]
DELETE FROM [dbo].[Sections]
DELETE FROM [dbo].[Venue]
GO

-- Ids pre-computed as md5 hash of UTF8 encoding of the normalized tenant name, converted to Int 
-- These are the id values that will be used by the client application and PowerShell scripts to 
-- retrieve tenant-specific data.   
DECLARE @FabrikamId INT = 1536234342

-- Venue
INSERT INTO [dbo].[Venue]
   ([VenueId],[VenueName],[VenueType],[AdminEmail],[AdminPassword],[PostalCode],[CountryCode],[Lock])
     VALUES
           (@FabrikamId, 'Fabrikam Jazz Club','jazz','admin@fabrikamjazzclub.com',NULL,'98052','USA','X')
GO

-- Sections
SET IDENTITY_INSERT [dbo].[Sections] ON
INSERT INTO [dbo].[Sections]
    ([SectionId],[SectionName],[SeatRows],[SeatsPerRow],[StandardPrice])
    VALUES
    (1,'VIP',2,20,90.00),
    (2,'Main',8,30,60.00)
;
SET IDENTITY_INSERT [dbo].[Sections] OFF
GO

-- Events
SET IDENTITY_INSERT [dbo].[Events] ON
INSERT INTO [dbo].[Events]
    ([EventId],[EventName],[Subtitle],[Date])
    VALUES
    (1,'Jambalaya Jazz','Bayou Banjo Quartet','2017-02-10 20:00:00'),
    (2,'Rhythm Rhymes', 'Rhythm Roots Trio', '2017-02-11 20:00:00'),
    (3,'Jazz Grabbs You','Torsten and the Grabbs','2017-02-12 20:00:00'),
    (4,'Smokey Sam on Fire','Smokey Sam and the Scorchers', '2017-02-13 20:00:00'),
    (5,'Jazz Masquerades','Fabrikam Jazz Band','2017-02-14 20:00:00'),
    (6,'Latin Jazz Discovery','Little Louis Latin Jazz Band ','2017-02-15 20:00:00'),
    (7,'Late Night Jazz Jam','Jim Jam Jazz Band','2017-02-16 20:00:00'),
    (8,'Jazz Journey','Fabrikam Jazz Band','2017-02-17 20:00:00'),
    (9,'One Flew Over','Cuckoo Nest Quartet', '2017-02-18 20:00:00'),
    (10,'Main Street Jamboree','Cross Rhodes with guest, Side Street','2017-02-19 20:00:00'),
    (11,'Flight of Fancy','Debra and the Dove Band','2017-02-19 20:00:00') 
;
SET IDENTITY_INSERT [dbo].[Events] OFF
GO

-- Event Sections
INSERT INTO [dbo].[EventSections]
    ([EventId],[SectionId],[Price])
    VALUES
    (1,1,90.00),
    (1,2,60.00),
    (2,1,100.00),
    (2,2,80.00),
    (3,1,150.00),
    (3,2,100.00),
    (4,1,90.00),
    (4,2,60.00),
    (5,1,100.00),
    (5,2,80.00),
    (6,1,100.00),
    (6,2,80.00),
    (7,1,100.00),
    (7,2,80.00),
    (8,1,120.00),
    (8,2,90.00),
    (9,1,95.00),
    (9,2,65.00),
    (10,1,90.00),
    (10,2,60.00),
    (11,1,100.00),
    (11,2,90.00)
;
GO

