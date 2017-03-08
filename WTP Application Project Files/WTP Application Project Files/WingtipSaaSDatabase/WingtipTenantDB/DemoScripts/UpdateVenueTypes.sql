-- Extend the set of VenueTypes using an idempotent MERGE script
--
MERGE INTO [dbo].[VenueTypes] AS [target]
USING (VALUES
    ('MultiPurposeVenue','Multi Purpose Venue','Event', 'Event','Events','en-us'),
    ('ClassicalConcertHall','Classical Concert Hall','Classical Concert','Concert','Concerts','en-us'),
    ('JazzClub','Jazz Club','Jazz Session','Session','Sessions','en-us'),
    ('JudoClub','Judo Club','Judo Tournament','Tournament','Tournaments','en-us'),
    ('SoccerClub','Soccer Club','Soccer Match', 'Match','Matches','en-us'),
    ('MotorRacing','Motor Racing','Car Race', 'Race','Races','en-us'),
    ('DanceStudio', 'Dance Studio', 'Performance', 'Performance', 'Performances','en-us'),
    ('BluesClub', 'Blues Club', 'Blues Session', 'Session','Sessions','en-us' ),
    ('RockMusicVenue','Rock Music Venue','Rock Concert','Concert', 'Concerts','en-us'),
    ('Opera','Opera','Opera','Opera','Operas','en-us'),
    ('MotorCycleRacing','Motorcycle Racing','Motorcycle Race', 'Race', 'Races', 'en-us'), -- NEW
    ('SwimmingClub','Swimming Club','Swimming Race','Race','Races','en-us') -- NEW
) AS source(
    VenueType,VenueTypeName,EventTypeName,EventTypeShortName,EventTypeShortNamePlural,[Language]
)              
ON [target].VenueType = source.VenueType
-- update existing rows
WHEN MATCHED THEN
    UPDATE SET 
        VenueTypeName = source.VenueTypeName,
        EventTypeName = source.EventTypeName,
        EventTypeShortName = source.EventTypeShortName,
        EventTypeShortNamePlural = source.EventTypeShortNamePlural,
        [Language] = source.[Language]
-- insert new rows
WHEN NOT MATCHED BY TARGET THEN
    INSERT (VenueType,VenueTypeName,EventTypeName,EventTypeShortName,EventTypeShortNamePlural,[Language])
    VALUES (VenueType,VenueTypeName,EventTypeName,EventTypeShortName,EventTypeShortNamePlural,[Language])
;
GO
