CREATE TABLE [dbo].[Databases]
(
    [ServerName] NVARCHAR(128) NOT NULL,   
    [DatabaseName] NVARCHAR(128) NOT NULL,
    [ServiceObjective] NVARCHAR(50) NOT NULL, 
    [ElasticPoolName] NVARCHAR(128) NULL, 
    [State] NVARCHAR(30) NOT NULL DEFAULT 'initial',
    [RecoveryState] NVARCHAR(30) NULL,
    [LastUpdated] DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [PK_Databases] PRIMARY KEY CLUSTERED ([ServerName],[DatabaseName])
)