CREATE TABLE [dbo].[VenueTypes]
(
    [VenueType]                 NVARCHAR(30) NOT NULL,
	[VenueTypeName]             NVARCHAR(30) NOT NULL,  
    [EventTypeName]             NVARCHAR(30) NOT NULL, 
	[EventTypeShortName]        NVARCHAR(20) NOT NULL,
	[EventTypeShortNamePlural]  NVARCHAR(20) NOT NULL,
    [Language]                  NVARCHAR(10) NOT NULL,
    PRIMARY KEY CLUSTERED ([VenueType] ASC),
    CONSTRAINT [AK_VenueType_VenueTypeName_Language] UNIQUE ([VenueTypeName], [Language])
)
GO


