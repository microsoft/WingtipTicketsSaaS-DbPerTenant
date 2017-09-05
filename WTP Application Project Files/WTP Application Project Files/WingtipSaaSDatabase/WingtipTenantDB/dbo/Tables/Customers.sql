CREATE TABLE [dbo].[Customers] (
    [CustomerId]        INT               IDENTITY (1, 1) NOT NULL,
    [FirstName]         NVARCHAR (50)      NOT NULL,
    [LastName]          NVARCHAR (50)      NOT NULL,
    [Email]             VARCHAR (128)      NOT NULL,
    [Password]          NVARCHAR (30)      NULL,
    [PostalCode]        NVARCHAR(20) NULL, 
    [CountryCode]       CHAR(3) NOT NULL,
    [RowVersion]        ROWVERSION NOT NULL, 
    PRIMARY KEY CLUSTERED ([CustomerId] ASC), 
    CONSTRAINT [AK_Email] UNIQUE (Email),
    CONSTRAINT [FK_Customers_Countries] FOREIGN KEY ([CountryCode]) REFERENCES [Countries]([CountryCode])
);


GO

CREATE UNIQUE INDEX [IX_Customers_Email] ON [dbo].[Customers] (Email)
