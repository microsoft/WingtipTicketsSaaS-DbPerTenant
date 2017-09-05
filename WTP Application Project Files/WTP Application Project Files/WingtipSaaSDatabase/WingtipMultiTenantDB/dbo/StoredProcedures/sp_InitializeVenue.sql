CREATE PROCEDURE [dbo].[sp_InitializeVenue]
    @VenueId  INT NOT NULL,
    @VenueName NVARCHAR(128) NOT NULL,
    @VenueType NVARCHAR(30) = 'multipurpose',
    @CountryCode CHAR(3) = 'USA'
AS
    -- Insert Venue
    INSERT INTO [dbo].Venues
        ([VenueId],[VenueName],[VenueType],[AdminEmail],[CountryCode])         
    VALUES
        (@VenueId, @VenueName,@VenueType,'admin@email.com',@CountryCode)

    -- Insert default Sections
    SET IDENTITY_INSERT [dbo].[Sections] ON;

    INSERT INTO [dbo].[Sections]
        ([VenueId],[SectionId],[SectionName])
    VALUES
        (@VenueId,1,'Section 1'),
        (@VenueId,2,'Section 2');
    SET IDENTITY_INSERT [dbo].[Sections] OFF
    
    -- Insert default Events
    SET IDENTITY_INSERT [dbo].[Events] ON;

    INSERT INTO [dbo].[Events]
        ([VenueId],[EventId],[EventName],[Subtitle],[Date])     
    VALUES
        (@VenueId,1,'Event 1','Performer 1','2017-02-11 20:00:00'),
        (@VenueId,2,'Event 2','Performer 2','2017-02-12 20:00:00'),
        (@VenueId,3,'Event 3','Performer 3','2017-02-13 20:00:00'),
        (@VenueId,4,'Event 4','Performer 4','2017-02-14 20:00:00'),
        (@VenueId,5,'Event 5','Performer 5','2017-02-14 20:00:00');

    SET IDENTITY_INSERT [dbo].[Events] OFF

    -- Insert default EventSections

    INSERT INTO [dbo].[EventSections]
        ([VenueId],[EventId],[SectionId],[Price])
    VALUES
        (@VenueId,1,1,40.00),
        (@VenueId,1,2,20.00),
        (@VenueId,2,1,40.00),
        (@VenueId,2,2,20.00),    
        (@VenueId,3,1,40.00),
        (@VenueId,3,2,20.00),
        (@VenueId,4,1,40.00),
        (@VenueId,4,2,20.00),
        (@VenueId,5,1,40.00),
        (@VenueId,5,2,20.00);

RETURN 0
