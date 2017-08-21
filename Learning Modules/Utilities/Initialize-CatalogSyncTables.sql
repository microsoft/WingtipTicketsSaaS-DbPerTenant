DROP TABLE IF EXISTS dbo.[Servers]
GO

CREATE TABLE [dbo].[Servers]
(
    [ServerName] NVARCHAR(128) NOT NULL PRIMARY KEY, 
    [Location] NVARCHAR (30) NOT NULL,
    [State] NVARCHAR(30) NOT NULL DEFAULT 'initial',
    [LastUpdated] DATETIME NULL 
)

DROP TABLE IF EXISTS dbo.ElasticPools
GO

CREATE TABLE [dbo].[ElasticPools]
( 
    [ServerName] NVARCHAR(128) NOT NULL,
    [ElasticPoolName] NVARCHAR(128) NOT NULL, 
    [Dtu] INT NOT NULL, 
    [Edition] VARCHAR(20) NOT NULL, 
    [DatabaseDtuMax] INT NOT NULL, 
    [DatabaseDtuMin] INT NOT NULL,
    [StorageMB] INT NOT NULL, 
    [State] NVARCHAR(30) NOT NULL DEFAULT 'initial',
    [LastUpdated] DATETIME NULL, 
    CONSTRAINT [PK_ElasticPools] PRIMARY KEY ([ServerName], [ElasticPoolName])   
)


DROP TABLE IF EXISTS dbo.[Databases]
GO

CREATE TABLE [dbo].[Databases]
(
    [ServerName] NVARCHAR(128) NOT NULL,   
    [DatabaseName] NVARCHAR(128) NOT NULL,
    [ServiceObjective] NVARCHAR(50) NOT NULL, 
    [ElasticPoolName] NVARCHAR(128) NULL, 
    [State] NVARCHAR(30) NOT NULL DEFAULT 'initial',
    [LastUpdated] DATETIME NULL
)
GO

ALTER TABLE [dbo].[Databases]
ADD CONSTRAINT PK_Databases PRIMARY KEY CLUSTERED ([ServerName],[DatabaseName])
GO