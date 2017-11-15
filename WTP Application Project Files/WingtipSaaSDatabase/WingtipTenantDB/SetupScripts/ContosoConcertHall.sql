-- Contoso Concert Hall Initialization
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

-- Ids pre-computed as md5 hash of UTF8 encoding of the normalized tenant name, converted to Int 
-- These are the id values that will be used by the client application and PowerShell scripts to 
-- retrieve tenant-specific data.   
DECLARE @ContosoId INT = 1976168774

-- Venue
INSERT INTO [dbo].[Venue]
   ([VenueId],[VenueName],[VenueType],[AdminEmail],[AdminPassword],[PostalCode],[CountryCode],[Lock])
     VALUES
           (@ContosoId,'Contoso Concert Hall','classicalmusic','admin@contosoconcerthall.com',NULL,'98052','USA','X')
GO

-- Sections
SET IDENTITY_INSERT [dbo].[Sections] ON
INSERT INTO [dbo].[Sections]
    ([SectionId],[SectionName],[SeatRows],[SeatsPerRow],[StandardPrice])
    VALUES
    (1,'Main Auditorium Stage',10,30,100.00),
    (2,'Main Auditorium Middle',10,30,80.00),
    (3,'Main Auditorium Rear',10,30,60.00),
    (4,'Balcony',10,30,40.00)
;
SET IDENTITY_INSERT [dbo].[Sections] OFF

-- Events
SET IDENTITY_INSERT [dbo].[Events] ON
INSERT INTO [dbo].[Events]
    ([EventId],[EventName],[Subtitle],[Date])
    VALUES
    (1,'String Serenades','Contoso Chamber Orchestra','2017-02-10 20:00:00'),
    (2,'Concert Pops', 'Contoso Symphony', '2017-02-11 20:00:00'),
    (3,'A Musical Journey','Contoso Symphony','2017-02-12 20:00:00'),
    (4,'A Night at the Opera','Contoso Choir', '2017-02-13 20:00:00'),
    (5,'An Evening with Tchaikovsky','Contoso Symphony','2017-02-14 20:00:00'),
    (6,'Lend me a Tenor','Contoso Choir','2017-02-15 20:00:00'),
    (7,'Chamber Music Medley','Contoso Chamber Orchestra','2017-02-16 20:00:00'),
    (8,'The 1812 Overture','Contoso Symphony','2017-02-17 20:00:00'),
    (9,'Handel''s Messiah','Contoso Symphony', '2017-02-18 20:00:00'),
    (10,'Moonlight Serenade','Contoso Quartet','2017-02-19 20:00:00'),
    (11,'Seriously Strauss', 'Julie von Strauss Septet','2017-02-20 20:00:00') 
;
SET IDENTITY_INSERT [dbo].[Events] OFF
GO

-- Event Sections
INSERT INTO [dbo].[EventSections]
    ([EventId],[SectionId],[Price])
    VALUES
    (1,1,100.00),
    (1,2,80.00),
    (1,3,60.00),
    (1,4,40.00),
    (2,1,100.00),
    (2,2,80.00),
    (2,3,60.00),
    (2,4,40.00),
    (3,1,100.00),
    (3,2,80.00),
    (3,3,60.00),
    (3,4,40.00),   
    (4,1,100.00),
    (4,2,80.00),
    (4,3,60.00),
    (4,4,40.00),
    (5,1,100.00),
    (5,2,80.00),
    (5,3,60.00),
    (5,4,40.00),
    (6,1,100.00),
    (6,2,80.00),
    (6,3,60.00),
    (6,4,40.00),
    (7,1,100.00),
    (7,2,80.00),
    (7,3,60.00),
    (7,4,40.00),
    (8,1,100.00),
    (8,2,80.00),
    (8,3,60.00),
    (8,4,40.00),
    (9,1,100.00),
    (9,2,80.00),
    (9,3,60.00),
    (9,4,40.00),
    (10,1,100.00),
    (10,2,80.00),
    (10,3,60.00),
    (10,4,40.00),
    (11,1,150.00),
    (11,2,100.00),
    (11,3,90.00),
    (11,4,60.00)
;

