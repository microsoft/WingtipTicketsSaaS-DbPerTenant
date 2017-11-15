-- Dogwood Dojo Initialization
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
DECLARE @DogwoodId INT = -1368421345

-- Venue
INSERT INTO [dbo].[Venue]
   ([VenueId],[VenueName],[VenueType],[AdminEmail],[AdminPassword],[PostalCode],[CountryCode], [Lock])
     VALUES
           (@DogwoodId, 'Dogwood Dojo','judo','admin@dogwooddojo.com',NULL,'98052','USA','X')
GO

-- Sections
SET IDENTITY_INSERT [dbo].[Sections] ON
INSERT INTO [dbo].[Sections]
    ([SectionId],[SectionName],[SeatRows],[SeatsPerRow],[StandardPrice])
    VALUES
    (1,'RingSide',4,50,30.00),
    (2,'End',6,20,20.00),
    (3,'Outer', 3,60,15.00)
;
SET IDENTITY_INSERT [dbo].[Sections] OFF
GO

-- Events
SET IDENTITY_INSERT [dbo].[Events] ON
INSERT INTO [dbo].[Events]
    ([EventId],[EventName],[Subtitle],[Date])
    VALUES
    (1,'International Challenge','Open International','2017-02-10 20:00:00'),
    (2,'Junior Open', 'Local Juniors', '2017-02-11 20:00:00'),
    (3,'State Champions Exhibition','State Champions, All Levels','2017-02-12 20:00:00'),
    (4,'Exhibition Match','Dogwood Exhibition Team', '2017-02-13 20:00:00'),
    (5,'All-Comers Challenge','Open','2017-02-14 20:00:00'),
    (6,'Freestyle','Local Champions','2017-02-15 20:00:00'),
    (7,'Dogwood Doggies','The Dogwood Junior Team','2017-02-16 20:00:00'),
    (8,'Senior Open','Local Seniors','2017-02-17 20:00:00'),
    (9,'Masters Open','Local Masters', '2017-02-18 20:00:00'),
    (10,'Dojo Downlow','Surprise Guest, Exhibition','2017-02-19 20:00:00'),
    (11,'Dogwood Regional Finals', 'Regional Champions','2017-02-20 20:00:00') 
;
SET IDENTITY_INSERT [dbo].[Events] OFF
GO

-- Event Sections
INSERT INTO [dbo].[EventSections]
    ([EventId],[SectionId],[Price])
    VALUES
    (1,1,40.00),
    (1,2,30.00),
    (1,3,20.00),    
    (2,1,30.00),
    (2,2,20.00),
    (2,3,10.00), 
    (3,1,30.00),
    (3,2,20.00),
    (3,3,10.00), 
    (4,1,40.00),
    (4,2,30.00),
    (4,3,20.00), 
    (5,1,20.00),
    (5,2,12.00),
    (5,3,8.00),
    (6,1,30.00),
    (6,2,20.00),
    (6,3,10.00),
    (7,1,2.00),
    (7,2,2.00),
    (7,3,2.00),
    (8,1,30.00),
    (8,2,20.00),
    (8,3,10.00),
    (9,1,35.00),
    (9,2,25.00),
    (9,3,15.00),
    (10,1,25.00),
    (10,2,17.00),
    (10,3,9.00),
    (11,1,45.00),
    (11,2,35.00),
    (11,3,20.00)
;
GO

