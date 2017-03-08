CREATE TABLE [dbo].[Customers] (
    [CustomerId]        INT               IDENTITY (1, 1) NOT NULL,
    [FirstName]         NVARCHAR (25)      NOT NULL,
    [LastName]          NVARCHAR (25)      NOT NULL,
    [Email]             VARCHAR (30)      NOT NULL,
    [Password]          NVARCHAR (30)      NULL,
    [PostalCode]        CHAR(10) NULL, 
    [CountryCode]         CHAR(3) NOT NULL,
    PRIMARY KEY CLUSTERED ([CustomerId] ASC), 
    CONSTRAINT [FK_Customers_Countries] FOREIGN KEY ([CountryCode]) REFERENCES [Countries]([CountryCode])
);


GO

CREATE UNIQUE INDEX [IX_Customers_Email] ON [dbo].[Customers] (Email)
