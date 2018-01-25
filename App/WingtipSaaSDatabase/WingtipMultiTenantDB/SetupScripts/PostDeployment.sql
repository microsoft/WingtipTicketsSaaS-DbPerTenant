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
