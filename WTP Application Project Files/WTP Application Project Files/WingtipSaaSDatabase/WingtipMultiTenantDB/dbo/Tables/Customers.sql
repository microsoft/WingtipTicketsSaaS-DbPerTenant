CREATE TABLE [dbo].[Customers] (
    [VenueId]           INT NOT NULL,
    [CustomerId]        INT IDENTITY NOT NULL ,
    [FirstName]         NVARCHAR (50)      NOT NULL,
    [LastName]          NVARCHAR (50)      NOT NULL,
    [Email]             VARCHAR (128)      NOT NULL,
    [Password]          NVARCHAR (30) NULL,
    [PostalCode]        NVARCHAR(20)  NULL, 
    [CountryCode]       CHAR(3)       NOT NULL,
    [RowVersion]        ROWVERSION    NOT NULL, 
    PRIMARY KEY CLUSTERED ([VenueId],[CustomerId] ASC),
    CONSTRAINT [AK_Venue_Email] UNIQUE (VenueId, Email),
    CONSTRAINT [FK_Customers_Venues] FOREIGN KEY ([VenueId]) REFERENCES [Venues]([VenueId]),
    CONSTRAINT [FK_Customers_Countries] FOREIGN KEY ([CountryCode]) REFERENCES [Countries]([CountryCode])
);

GO
