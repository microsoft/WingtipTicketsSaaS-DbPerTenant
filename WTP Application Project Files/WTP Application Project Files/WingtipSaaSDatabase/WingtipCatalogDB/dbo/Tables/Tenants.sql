CREATE TABLE [dbo].[Tenants]
(
    [TenantId]      VARBINARY(128) NOT NULL,
    [TenantName]    NVARCHAR(50) NOT NULL,
    [ServicePlan]   CHAR(10) NOT NULL DEFAULT 'standard', 
    PRIMARY KEY CLUSTERED ([TenantId]), 
    CONSTRAINT [CK_Tenants_ServicePlan] CHECK ([ServicePlan] in ('free','standard','premium'))     
)

GO

CREATE INDEX [IX_Tenants_TenantName] ON [dbo].[Tenants] ([TenantName])
GO

CREATE INDEX [IX_Tenants_TenantId] ON [dbo].[Tenants] ([TenantId])
GO