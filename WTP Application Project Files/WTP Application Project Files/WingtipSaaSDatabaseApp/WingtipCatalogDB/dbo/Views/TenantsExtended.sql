CREATE VIEW TenantsExtended AS
SELECT TenantId, TenantName, ServerName, DatabaseName
    FROM [dbo].[Tenants] AS tenant
    INNER JOIN [__ShardManagement].[ShardMappingsGlobal] AS mapping 
        ON tenant.TenantId = mapping.MinValue 
    INNER JOIN [__ShardManagement].[ShardMapsGlobal] AS map 
        ON map.ShardMapId = mapping.ShardMapId
	INNER JOIN [__ShardManagement].[ShardsGlobal] as shard 
        ON  shard.ShardId = mapping.ShardId AND 
            shard.ShardMapId = map.ShardMapId AND 
            mapping.ShardMapId = map.ShardMapId
    WHERE map.name = 'CustomerCatalog'
;	 