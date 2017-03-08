CREATE TABLE [dbo].[Countries]
(
	[CountryCode]   CHAR(3) NOT NULL,
	[CountryName]   NVARCHAR(50) NOT NULL,
	[Language]      CHAR(8) NOT NULL DEFAULT 'en',
	PRIMARY KEY CLUSTERED ([CountryCode] ASC)
)

GO

CREATE UNIQUE INDEX IX_Countries_Country_Language ON [dbo].[Countries] ([CountryCode], [Language]); 
