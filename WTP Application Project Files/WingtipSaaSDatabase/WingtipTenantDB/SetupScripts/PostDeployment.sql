/*

Post-Deployment Script Template                            
--------------------------------------------------------------------------------------
 This file contains SQL statements that will be appended to the build script.        
 Use SQLCMD syntax to include a file in the post-deployment script.            
 Example:      :r .\myfile.sql                                
 Use SQLCMD syntax to reference a variable in the post-deployment script.        
 Example:      :setvar TableName MyTable                            
               SELECT * FROM [$(TableName)]                    
--------------------------------------------------------------------------------------
*/

-- Country code is based on ISO 3166-1 alpha-3 codes.  See https://en.wikipedia.org/wiki/ISO_3166-1_alpha-3

INSERT INTO [dbo].[Countries]
    ([CountryCode],[CountryName],[Language])
VALUES
    ('USA', 'United States','en-us')
GO

INSERT INTO [dbo].[VenueTypes]
    ([VenueType],[VenueTypeName],[EventTypeName],[EventTypeShortName],[EventTypeShortNamePlural],[Language])
VALUES
    ('multipurpose','Multi-Purpose Venue','Event', 'Event','Events','en-us'),
    ('classicalmusic','Classical Music Venue','Classical Concert','Concert','Concerts','en-us'),
    ('jazz','Jazz Venue','Jazz Session','Session','Sessions','en-us'),
    ('judo','Judo Venue','Judo Tournament','Tournament','Tournaments','en-us'),
    ('soccer','Soccer Venue','Soccer Match', 'Match','Matches','en-us'),
    ('motorracing','Motor Racing Venue','Car Race', 'Race','Races','en-us'),
    ('dance', 'Dance Venue', 'Dance Performance', 'Performance', 'Performances','en-us'),
    ('blues', 'Blues Venue', 'Blues Session', 'Session','Sessions','en-us' ),
    ('rockmusic','Rock Music Venue','Rock Concert','Concert', 'Concerts','en-us'),
    ('opera','Opera Venue','Opera','Opera','Operas','en-us');      
GO

-- Ids pre-computed as md5 hash of UTF8 encoding of the normalized tenant name, converted to Int 
-- These are the id values that will be used by the client application and PowerShell scripts to 
-- retrieve tenant-specific data.   
DECLARE @VenueId INT = -1209177223

INSERT INTO [dbo].Venue
    ([VenueId], [VenueName],[VenueType],[AdminEmail],[CountryCode],[Lock])         
VALUES
    (@VenueId,'Venue Name','multipurpose','admin@email.com','USA','X')
GO


-- Sections
SET IDENTITY_INSERT [dbo].[Sections] ON;

INSERT INTO [dbo].[Sections]
    ([SectionId],[SectionName])
VALUES
    (1,'Section 1'),
    (2,'Section 2');

SET IDENTITY_INSERT [dbo].[Sections] OFF
GO

-- Events
SET IDENTITY_INSERT [dbo].[Events] ON;

INSERT INTO [dbo].[Events]
    ([EventId],[EventName],[Subtitle],[Date])     
VALUES
    (1,'Event 1','Performer 1','2017-02-11 20:00:00'),
    (2,'Event 2','Performer 2','2017-02-12 20:00:00'),
    (3,'Event 3','Performer 3','2017-02-13 20:00:00'),
    (4,'Event 4','Performer 4','2017-02-14 20:00:00'),
    (5,'Event 5','Performer 5','2017-02-14 20:00:00');

SET IDENTITY_INSERT [dbo].[Events] OFF
GO

-- Event Sections
INSERT INTO [dbo].[EventSections]
    ([EventId],[SectionId],[Price])
VALUES
    (1,1,40.00),
    (1,2,20.00),
    (2,1,40.00),
    (2,2,20.00),    
    (3,1,40.00),
    (3,2,20.00),
    (4,1,40.00),
    (4,2,20.00),
    (5,1,40.00),
    (5,2,20.00);
GO
