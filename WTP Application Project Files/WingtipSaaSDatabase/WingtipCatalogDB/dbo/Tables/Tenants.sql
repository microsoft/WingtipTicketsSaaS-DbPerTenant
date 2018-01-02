CREATE TABLE [dbo].[Tenants]
(
    [TenantId]      VARBINARY(128) NOT NULL,
    [TenantName]    NVARCHAR(50) NOT NULL,
	[TenantAlias]	NVARCHAR(65) NOT NULL,
    [ServicePlan]   NVARCHAR(30) NOT NULL DEFAULT 'Standard', 
    PRIMARY KEY CLUSTERED ([TenantId]), 
    RecoveryState NVARCHAR(30) NOT NULL DEFAULT 'n/a',
    LastUpdated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [CK_Tenants_ServicePlan] CHECK ([ServicePlan] in ('Free','Standard','Premium'))     
)

GO

CREATE INDEX [IX_Tenants_TenantName] ON [dbo].[Tenants] ([TenantName])
GO

CREATE INDEX [IX_Tenants_TenantId] ON [dbo].[Tenants] ([TenantId])
GO
