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

-- Venue
INSERT INTO [dbo].[Venues]
   ([VenueId],[VenueName],[VenueType],[AdminEmail],[AdminPassword],[PostalCode],[CountryCode])
     VALUES
           (1,'Contoso Concert Hall','classicalmusic','admin@contosoconcerthall.com',NULL,'98052','USA'),
           (2,'Dogwood Dojo','judo','admin@dogwooddojo.com',NULL,'98052','USA'),
           (3,'Fabrikam Jazz Club','jazz','admin@fabrikamjazzclub.com',NULL,'98052','USA')
GO

-- Contoso Concert Hall (VenueId=1)
-- Sections
SET IDENTITY_INSERT [dbo].[Sections] ON
INSERT INTO [dbo].[Sections]
    ([VenueId],[SectionId],[SectionName],[SeatRows],[SeatsPerRow],[StandardPrice])
    VALUES
    (1,1,'Main Auditorium Stage',10,30,100.00),
    (1,2,'Main Auditorium Middle',10,30,80.00),
    (1,3,'Main Auditorium Rear',10,30,60.00),
    (1,4,'Balcony',10,30,40.00)
;
SET IDENTITY_INSERT [dbo].[Sections] OFF

-- Events
SET IDENTITY_INSERT [dbo].[Events] ON
INSERT INTO [dbo].[Events]
    ([VenueId],[EventId],[EventName],[Subtitle],[Date])
    VALUES
    (1,1,'String Serenades','Contoso Chamber Orchestra','2017-02-10 20:00:00'),
    (1,2,'Concert Pops', 'Contoso Symphony', '2017-02-11 20:00:00'),
    (1,3,'A Musical Journey','Contoso Symphony','2017-02-12 20:00:00'),
    (1,4,'A Night at the Opera','Contoso Choir', '2017-02-13 20:00:00'),
    (1,5,'An Evening with Tchaikovsky','Contoso Symphony','2017-02-14 20:00:00'),
    (1,6,'Lend me a Tenor','Contoso Choir','2017-02-15 20:00:00'),
    (1,7,'Chamber Music Medley','Contoso Chamber Orchestra','2017-02-16 20:00:00'),
    (1,8,'The 1812 Overture','Contoso Symphony','2017-02-17 20:00:00'),
    (1,9,'Handel''s Messiah','Contoso Symphony', '2017-02-18 20:00:00'),
    (1,10,'Moonlight Serenade','Contoso Quartet','2017-02-19 20:00:00'),
    (1,11,'Seriously Strauss', 'Julie von Strauss Septet','2017-02-20 20:00:00') 
;
SET IDENTITY_INSERT [dbo].[Events] OFF
GO

-- Event Sections
INSERT INTO [dbo].[EventSections]
    ([VenueId],[EventId],[SectionId],[Price])
    VALUES
    (1,1,1,100.00),
    (1,1,2,80.00),
    (1,1,3,60.00),
    (1,1,4,40.00),
    (1,2,1,100.00),
    (1,2,2,80.00),
    (1,2,3,60.00),
    (1,2,4,40.00),
    (1,3,1,100.00),
    (1,3,2,80.00),
    (1,3,3,60.00),
    (1,3,4,40.00),   
    (1,4,1,100.00),
    (1,4,2,80.00),
    (1,4,3,60.00),
    (1,4,4,40.00),
    (1,5,1,100.00),
    (1,5,2,80.00),
    (1,5,3,60.00),
    (1,5,4,40.00),
    (1,6,1,100.00),
    (1,6,2,80.00),
    (1,6,3,60.00),
    (1,6,4,40.00),
    (1,7,1,100.00),
    (1,7,2,80.00),
    (1,7,3,60.00),
    (1,7,4,40.00),
    (1,8,1,100.00),
    (1,8,2,80.00),
    (1,8,3,60.00),
    (1,8,4,40.00),
    (1,9,1,100.00),
    (1,9,2,80.00),
    (1,9,3,60.00),
    (1,9,4,40.00),
    (1,10,1,100.00),
    (1,10,2,80.00),
    (1,10,3,60.00),
    (1,10,4,40.00),
    (1,11,1,150.00),
    (1,11,2,100.00),
    (1,11,3,90.00),
    (1,11,4,60.00)
;

-- Dogwood Dojo (VenueId=2)
-- Sections
SET IDENTITY_INSERT [dbo].[Sections] ON
INSERT INTO [dbo].[Sections]
    ([VenueId],[SectionId],[SectionName],[SeatRows],[SeatsPerRow],[StandardPrice])
    VALUES
    (2,1,'RingSide',4,50,30.00),
    (2,2,'End',6,20,20.00),
    (2,3,'Outer', 3,60,15.00)
;
SET IDENTITY_INSERT [dbo].[Sections] OFF
GO

-- Events
SET IDENTITY_INSERT [dbo].[Events] ON
INSERT INTO [dbo].[Events]
    ([VenueId],[EventId],[EventName],[Subtitle],[Date])
    VALUES
    (2,1,'International Challenge','Open International','2017-02-10 20:00:00'),
    (2,2,'Junior Open', 'Local Juniors', '2017-02-11 20:00:00'),
    (2,3,'State Champions Exhibition','State Champions, All Levels','2017-02-12 20:00:00'),
    (2,4,'Exhibition Match','Dogwood Exhibition Team', '2017-02-13 20:00:00'),
    (2,5,'All-Comers Challenge','Open','2017-02-14 20:00:00'),
    (2,6,'Freestyle','Local Champions','2017-02-15 20:00:00'),
    (2,7,'Dogwood Doggies','The Dogwood Junior Team','2017-02-16 20:00:00'),
    (2,8,'Senior Open','Local Seniors','2017-02-17 20:00:00'),
    (2,9,'Masters Open','Local Masters', '2017-02-18 20:00:00'),
    (2,10,'Dojo Downlow','Surprise Guest, Exhibition','2017-02-19 20:00:00'),
    (2,11,'Dogwood Regional Finals', 'Regional Champions','2017-02-20 20:00:00') 
;
SET IDENTITY_INSERT [dbo].[Events] OFF
GO

-- Event Sections
INSERT INTO [dbo].[EventSections]
    ([VenueId],[EventId],[SectionId],[Price])
    VALUES
    (2,1,1,40.00),
    (2,1,2,30.00),
    (2,1,3,20.00),    
    (2,2,1,30.00),
    (2,2,2,20.00),
    (2,2,3,10.00), 
    (2,3,1,30.00),
    (2,3,2,20.00),
    (2,3,3,10.00), 
    (2,4,1,40.00),
    (2,4,2,30.00),
    (2,4,3,20.00), 
    (2,5,1,20.00),
    (2,5,2,12.00),
    (2,5,3,8.00),
    (2,6,1,30.00),
    (2,6,2,20.00),
    (2,6,3,10.00),
    (2,7,1,2.00),
    (2,7,2,2.00),
    (2,7,3,2.00),
    (2,8,1,30.00),
    (2,8,2,20.00),
    (2,8,3,10.00),
    (2,9,1,35.00),
    (2,9,2,25.00),
    (2,9,3,15.00),
    (2,10,1,25.00),
    (2,10,2,17.00),
    (2,10,3,9.00),
    (2,11,1,45.00),
    (2,11,2,35.00),
    (2,11,3,20.00)
;
GO

-- Fabrikam Jazz Club (VenueId=3)
-- Sections
SET IDENTITY_INSERT [dbo].[Sections] ON
INSERT INTO [dbo].[Sections]
    ([VenueId],[SectionId],[SectionName],[SeatRows],[SeatsPerRow],[StandardPrice])
    VALUES
    (3,1,'VIP',2,20,90.00),
    (3,2,'Main',8,30,60.00)
;
SET IDENTITY_INSERT [dbo].[Sections] OFF
GO

-- Events
SET IDENTITY_INSERT [dbo].[Events] ON
INSERT INTO [dbo].[Events]
    ([VenueId],[EventId],[EventName],[Subtitle],[Date])
    VALUES
    (3,1,'Jambalaya Jazz','Bayou Banjo Quartet','2017-02-10 20:00:00'),
    (3,2,'Rhythm Rhymes', 'Rhythm Roots Trio', '2017-02-11 20:00:00'),
    (3,3,'Jazz Grabbs You','Torsten and the Grabbs','2017-02-12 20:00:00'),
    (3,4,'Smokey Sam on Fire','Smokey Sam and the Scorchers', '2017-02-13 20:00:00'),
    (3,5,'Jazz Masquerades','Fabrikam Jazz Band','2017-02-14 20:00:00'),
    (3,6,'Latin Jazz Discovery','Little Louis Latin Jazz Band ','2017-02-15 20:00:00'),
    (3,7,'Late Night Jazz Jam','Jim Jam Jazz Band','2017-02-16 20:00:00'),
    (3,8,'Jazz Journey','Fabrikam Jazz Band','2017-02-17 20:00:00'),
    (3,9,'One Flew Over','Cuckoo Nest Quartet', '2017-02-18 20:00:00'),
    (3,10,'Main Street Jamboree','Cross Rhodes with guest, Side Street','2017-02-19 20:00:00'),
    (3,11,'Flight of Fancy','Debra and the Dove Band','2017-02-19 20:00:00') 
;
SET IDENTITY_INSERT [dbo].[Events] OFF
GO

-- Event Sections
INSERT INTO [dbo].[EventSections]
    ([VenueId],[EventId],[SectionId],[Price])
    VALUES
    (3,1,1,90.00),
    (3,1,2,60.00),
    (3,2,1,100.00),
    (3,2,2,80.00),
    (3,3,1,150.00),
    (3,3,2,100.00),
    (3,4,1,90.00),
    (3,4,2,60.00),
    (3,5,1,100.00),
    (3,5,2,80.00),
    (3,6,1,100.00),
    (3,6,2,80.00),
    (3,7,1,100.00),
    (3,7,2,80.00),
    (3,8,1,120.00),
    (3,8,2,90.00),
    (3,9,1,95.00),
    (3,9,2,65.00),
    (3,10,1,90.00),
    (3,10,2,60.00),
    (3,11,1,100.00),
    (3,11,2,90.00)
;
GO

