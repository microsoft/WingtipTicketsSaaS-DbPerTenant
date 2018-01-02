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
    [RecoveryState] NVARCHAR(30) NULL,
    [LastUpdated] DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, 
    CONSTRAINT [PK_ElasticPools] PRIMARY KEY ([ServerName], [ElasticPoolName])   
)