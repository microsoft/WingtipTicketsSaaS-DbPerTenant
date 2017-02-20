CREATE TABLE [dbo].[VenueTypes]
(
    [VenueType]                 CHAR(30) NOT NULL,
	[VenueTypeName]             NCHAR(30) NOT NULL,  
    [EventTypeName]             NVARCHAR(30) NOT NULL, 
	[EventTypeShortName]        NVARCHAR(20) NOT NULL,
	[EventTypeShortNamePlural]  NVARCHAR(20) NOT NULL,
    [Language]                  CHAR(8) NOT NULL,
    PRIMARY KEY CLUSTERED ([VenueType] ASC)
)
GO

CREATE UNIQUE INDEX IX_VENUETYPES_VENUETYPE ON [dbo].[VenueTypes] ([VenueType])
GO

CREATE UNIQUE INDEX IX_VENUETYPES_VENUETYPENAME_LANGUAGE ON [dbo].[VenueTypes] ([VenueTypeName], [Language])
