-- Venue Initialization
--
-- All existing venue data will be deleted (excluding reference tables)
--
-----------------------------------------------------------------

-- Delete all current data
DELETE FROM [dbo].[Tickets]
DELETE FROM [dbo].[TicketPurchases]
DELETE FROM [dbo].[Customers]
DELETE FROM [dbo].[EventSections]
DELETE FROM [dbo].[Events]
DELETE FROM [dbo].[Sections]
DELETE FROM [dbo].[Venues]

-- Ids pre-computed as md5 hash of UTF8 encoding of the normalized tenant name, converted to Int 
-- These are the id values that will be used by the client application and PowerShell scripts to 
-- retrieve tenant-specific data.   
DECLARE @ContosoId INT = 1976168774
DECLARE @DogwoodId INT = -1368421345
DECLARE @FabrikamId INT = 1536234342

-- Venue
INSERT INTO [dbo].[Venues]
   ([VenueId],[VenueName],[VenueType],[AdminEmail],[AdminPassword],[PostalCode],[CountryCode])
     VALUES
           (@ContosoId,'Contoso Concert Hall','classicalmusic','admin@contosoconcerthall.com',NULL,'98052','USA'),
           (@DogwoodId,'Dogwood Dojo','judo','admin@dogwooddojo.com',NULL,'98052','USA'),
           (@FabrikamId,'Fabrikam Jazz Club','jazz','admin@fabrikamjazzclub.com',NULL,'98052','USA')

-- Sections
SET IDENTITY_INSERT [dbo].[Sections] ON
INSERT INTO [dbo].[Sections]
    ([VenueId],[SectionId],[SectionName],[SeatRows],[SeatsPerRow],[StandardPrice])
    VALUES
    (@ContosoId,1,'Main Auditorium Stage',10,30,100.00),
    (@ContosoId,2,'Main Auditorium Middle',10,30,80.00),
    (@ContosoId,3,'Main Auditorium Rear',10,30,60.00),
    (@ContosoId,4,'Balcony',10,30,40.00)
;
SET IDENTITY_INSERT [dbo].[Sections] OFF

-- Events
SET IDENTITY_INSERT [dbo].[Events] ON
INSERT INTO [dbo].[Events]
    ([VenueId],[EventId],[EventName],[Subtitle],[Date])
    VALUES
    (@ContosoId,1,'String Serenades','Contoso Chamber Orchestra','2017-02-10 20:00:00'),
    (@ContosoId,2,'Concert Pops', 'Contoso Symphony', '2017-02-11 20:00:00'),
    (@ContosoId,3,'A Musical Journey','Contoso Symphony','2017-02-12 20:00:00'),
    (@ContosoId,4,'A Night at the Opera','Contoso Choir', '2017-02-13 20:00:00'),
    (@ContosoId,5,'An Evening with Tchaikovsky','Contoso Symphony','2017-02-14 20:00:00'),
    (@ContosoId,6,'Lend me a Tenor','Contoso Choir','2017-02-15 20:00:00'),
    (@ContosoId,7,'Chamber Music Medley','Contoso Chamber Orchestra','2017-02-16 20:00:00'),
    (@ContosoId,8,'The 1812 Overture','Contoso Symphony','2017-02-17 20:00:00'),
    (@ContosoId,9,'Handel''s Messiah','Contoso Symphony', '2017-02-18 20:00:00'),
    (@ContosoId,10,'Moonlight Serenade','Contoso Quartet','2017-02-19 20:00:00'),
    (@ContosoId,11,'Seriously Strauss', 'Julie von Strauss Septet','2017-02-20 20:00:00') 
;
SET IDENTITY_INSERT [dbo].[Events] OFF

-- Event Sections
INSERT INTO [dbo].[EventSections]
    ([VenueId],[EventId],[SectionId],[Price])
    VALUES
    (@ContosoId,1,1,100.00),
    (@ContosoId,1,2,80.00),
    (@ContosoId,1,3,60.00),
    (@ContosoId,1,4,40.00),
    (@ContosoId,2,1,100.00),
    (@ContosoId,2,2,80.00),
    (@ContosoId,2,3,60.00),
    (@ContosoId,2,4,40.00),
    (@ContosoId,3,1,100.00),
    (@ContosoId,3,2,80.00),
    (@ContosoId,3,3,60.00),
    (@ContosoId,3,4,40.00),   
    (@ContosoId,4,1,100.00),
    (@ContosoId,4,2,80.00),
    (@ContosoId,4,3,60.00),
    (@ContosoId,4,4,40.00),
    (@ContosoId,5,1,100.00),
    (@ContosoId,5,2,80.00),
    (@ContosoId,5,3,60.00),
    (@ContosoId,5,4,40.00),
    (@ContosoId,6,1,100.00),
    (@ContosoId,6,2,80.00),
    (@ContosoId,6,3,60.00),
    (@ContosoId,6,4,40.00),
    (@ContosoId,7,1,100.00),
    (@ContosoId,7,2,80.00),
    (@ContosoId,7,3,60.00),
    (@ContosoId,7,4,40.00),
    (@ContosoId,8,1,100.00),
    (@ContosoId,8,2,80.00),
    (@ContosoId,8,3,60.00),
    (@ContosoId,8,4,40.00),
    (@ContosoId,9,1,100.00),
    (@ContosoId,9,2,80.00),
    (@ContosoId,9,3,60.00),
    (@ContosoId,9,4,40.00),
    (@ContosoId,10,1,100.00),
    (@ContosoId,10,2,80.00),
    (@ContosoId,10,3,60.00),
    (@ContosoId,10,4,40.00),
    (@ContosoId,11,1,150.00),
    (@ContosoId,11,2,100.00),
    (@ContosoId,11,3,90.00),
    (@ContosoId,11,4,60.00)
;

-- Dogwood Dojo
-- Sections
SET IDENTITY_INSERT [dbo].[Sections] ON
INSERT INTO [dbo].[Sections]
    ([VenueId],[SectionId],[SectionName],[SeatRows],[SeatsPerRow],[StandardPrice])
    VALUES
    (@DogwoodId,1,'RingSide',4,50,30.00),
    (@DogwoodId,2,'End',6,20,20.00),
    (@DogwoodId,3,'Outer', 3,60,15.00)
;
SET IDENTITY_INSERT [dbo].[Sections] OFF

-- Events
SET IDENTITY_INSERT [dbo].[Events] ON
INSERT INTO [dbo].[Events]
    ([VenueId],[EventId],[EventName],[Subtitle],[Date])
    VALUES
    (@DogwoodId,1,'International Challenge','Open International','2017-02-10 20:00:00'),
    (@DogwoodId,2,'Junior Open', 'Local Juniors', '2017-02-11 20:00:00'),
    (@DogwoodId,3,'State Champions Exhibition','State Champions, All Levels','2017-02-12 20:00:00'),
    (@DogwoodId,4,'Exhibition Match','Dogwood Exhibition Team', '2017-02-13 20:00:00'),
    (@DogwoodId,5,'All-Comers Challenge','Open','2017-02-14 20:00:00'),
    (@DogwoodId,6,'Freestyle','Local Champions','2017-02-15 20:00:00'),
    (@DogwoodId,7,'Dogwood Doggies','The Dogwood Junior Team','2017-02-16 20:00:00'),
    (@DogwoodId,8,'Senior Open','Local Seniors','2017-02-17 20:00:00'),
    (@DogwoodId,9,'Masters Open','Local Masters', '2017-02-18 20:00:00'),
    (@DogwoodId,10,'Dojo Downlow','Surprise Guest, Exhibition','2017-02-19 20:00:00'),
    (@DogwoodId,11,'Dogwood Regional Finals', 'Regional Champions','2017-02-20 20:00:00') 
;
SET IDENTITY_INSERT [dbo].[Events] OFF

-- Event Sections
INSERT INTO [dbo].[EventSections]
    ([VenueId],[EventId],[SectionId],[Price])
    VALUES
    (@DogwoodId,1,1,40.00),
    (@DogwoodId,1,2,30.00),
    (@DogwoodId,1,3,20.00),    
    (@DogwoodId,2,1,30.00),
    (@DogwoodId,2,2,20.00),
    (@DogwoodId,2,3,10.00), 
    (@DogwoodId,3,1,30.00),
    (@DogwoodId,3,2,20.00),
    (@DogwoodId,3,3,10.00), 
    (@DogwoodId,4,1,40.00),
    (@DogwoodId,4,2,30.00),
    (@DogwoodId,4,3,20.00), 
    (@DogwoodId,5,1,20.00),
    (@DogwoodId,5,2,12.00),
    (@DogwoodId,5,3,8.00),
    (@DogwoodId,6,1,30.00),
    (@DogwoodId,6,2,20.00),
    (@DogwoodId,6,3,10.00),
    (@DogwoodId,7,1,2.00),
    (@DogwoodId,7,2,2.00),
    (@DogwoodId,7,3,2.00),
    (@DogwoodId,8,1,30.00),
    (@DogwoodId,8,2,20.00),
    (@DogwoodId,8,3,10.00),
    (@DogwoodId,9,1,35.00),
    (@DogwoodId,9,2,25.00),
    (@DogwoodId,9,3,15.00),
    (@DogwoodId,10,1,25.00),
    (@DogwoodId,10,2,17.00),
    (@DogwoodId,10,3,9.00),
    (@DogwoodId,11,1,45.00),
    (@DogwoodId,11,2,35.00),
    (@DogwoodId,11,3,20.00)
;


-- Fabrikam Jazz Club
-- Sections
SET IDENTITY_INSERT [dbo].[Sections] ON
INSERT INTO [dbo].[Sections]
    ([VenueId],[SectionId],[SectionName],[SeatRows],[SeatsPerRow],[StandardPrice])
    VALUES
    (@FabrikamId,1,'VIP',2,20,90.00),
    (@FabrikamId,2,'Main',8,30,60.00)
;
SET IDENTITY_INSERT [dbo].[Sections] OFF

-- Events
SET IDENTITY_INSERT [dbo].[Events] ON
INSERT INTO [dbo].[Events]
    ([VenueId],[EventId],[EventName],[Subtitle],[Date])
    VALUES
    (@FabrikamId,1,'Jambalaya Jazz','Bayou Banjo Quartet','2017-02-10 20:00:00'),
    (@FabrikamId,2,'Rhythm Rhymes', 'Rhythm Roots Trio', '2017-02-11 20:00:00'),
    (@FabrikamId,3,'Jazz Grabbs You','Torsten and the Grabbs','2017-02-12 20:00:00'),
    (@FabrikamId,4,'Smokey Sam on Fire','Smokey Sam and the Scorchers', '2017-02-13 20:00:00'),
    (@FabrikamId,5,'Jazz Masquerades','Fabrikam Jazz Band','2017-02-14 20:00:00'),
    (@FabrikamId,6,'Latin Jazz Discovery','Little Louis Latin Jazz Band ','2017-02-15 20:00:00'),
    (@FabrikamId,7,'Late Night Jazz Jam','Jim Jam Jazz Band','2017-02-16 20:00:00'),
    (@FabrikamId,8,'Jazz Journey','Fabrikam Jazz Band','2017-02-17 20:00:00'),
    (@FabrikamId,9,'One Flew Over','Cuckoo Nest Quartet', '2017-02-18 20:00:00'),
    (@FabrikamId,10,'Main Street Jamboree','Cross Rhodes with guest, Side Street','2017-02-19 20:00:00'),
    (@FabrikamId,11,'Flight of Fancy','Debra and the Dove Band','2017-02-19 20:00:00') 
;
SET IDENTITY_INSERT [dbo].[Events] OFF

-- Event Sections
INSERT INTO [dbo].[EventSections]
    ([VenueId],[EventId],[SectionId],[Price])
    VALUES
    (@FabrikamId,1,1,90.00),
    (@FabrikamId,1,2,60.00),
    (@FabrikamId,2,1,100.00),
    (@FabrikamId,2,2,80.00),
    (@FabrikamId,3,1,150.00),
    (@FabrikamId,3,2,100.00),
    (@FabrikamId,4,1,90.00),
    (@FabrikamId,4,2,60.00),
    (@FabrikamId,5,1,100.00),
    (@FabrikamId,5,2,80.00),
    (@FabrikamId,6,1,100.00),
    (@FabrikamId,6,2,80.00),
    (@FabrikamId,7,1,100.00),
    (@FabrikamId,7,2,80.00),
    (@FabrikamId,8,1,120.00),
    (@FabrikamId,8,2,90.00),
    (@FabrikamId,9,1,95.00),
    (@FabrikamId,9,2,65.00),
    (@FabrikamId,10,1,90.00),
    (@FabrikamId,10,2,60.00),
    (@FabrikamId,11,1,100.00),
    (@FabrikamId,11,2,90.00)
;
GO

