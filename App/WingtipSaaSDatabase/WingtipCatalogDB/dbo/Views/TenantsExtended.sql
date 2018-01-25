DROP VIEW IF EXISTS [dbo].[TenantsExtended]
GO

CREATE VIEW [dbo].[TenantsExtended]
    AS        
        WITH databasesWithPriority AS (
            SELECT *, RANK() OVER (PARTITION BY DatabaseName ORDER BY LastUpdated DESC) AS databasePriority FROM Databases  
        )
        SELECT      tenant.TenantId,
                    tenant.TenantName,
                    CASE
                        WHEN mapping.Status = 1 THEN 'Online'
                        WHEN mapping.Status = 0 THEN 'Offline'
                    ELSE 'Unknown'
                    END AS TenantStatus,
                    tenant.ServicePlan,
                    CASE
                        WHEN ((shard.ServerName NOT LIKE '%home.database.windows.net') AND (shard.ServerName NOT LIKE '%recovery.database.windows.net')) THEN shard.ServerName
                        ELSE NULL
                    END AS TenantAlias,
                    CASE
                        WHEN ((shard.ServerName LIKE '%home.database.windows.net') OR (shard.ServerName LIKE '%recovery.database.windows.net')) THEN shard.ServerName
                        ELSE tenantDB.ServerName
                    END AS ServerName,
                    shard.DatabaseName,
                    tenant.RecoveryState AS TenantRecoveryState,
                    tenantServer.Location,
                    CASE
                        WHEN tenantDB.LastUpdated IS NULL THEN tenant.LastUpdated
                        WHEN (tenantDB.LastUpdated > tenant.LastUpdated) THEN tenantDB.LastUpdated
                        WHEN (tenantDB.LastUpdated < tenant.LastUpdated) THEN tenant.LastUpdated
                        ELSE tenant.LastUpdated
                    END AS LastUpdated
        FROM        [dbo].[Tenants] AS tenant
        JOIN        [__ShardManagement].[ShardMappingsGlobal] AS mapping ON (tenant.TenantId = mapping.MinValue)
        JOIN        [__ShardManagement].[ShardMapsGlobal] AS map ON (map.ShardMapId = mapping.ShardMapId)
        JOIN        [__ShardManagement].[ShardsGlobal] as shard ON (shard.ShardId = mapping.ShardId AND shard.ShardMapId = map.ShardMapId AND mapping.ShardMapId = map.ShardMapId)
        LEFT JOIN   databasesWithPriority AS tenantDB ON (tenantDB.DatabaseName = shard.DatabaseName AND tenantDB.databasePriority = 1)
        LEFT JOIN   Servers AS tenantServer ON (tenantServer.ServerName = tenantDB.ServerName)
        WHERE       (map.Name = 'tenantcatalog'); 