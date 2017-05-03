using System.Collections.Generic;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;

namespace Events_Tenant.Common.Helpers
{
    public interface IHelper
    {
        string GetBasicSqlConnectionString(DatabaseConfig databaseConfig);

        string GetSqlConnectionString(DatabaseConfig databaseConfig, CatalogConfig catalogConfig);

        void RegisterTenantShard(TenantServerConfig tenantServerConfig, DatabaseConfig databaseConfig,
            CatalogConfig catalogConfig, bool resetEventDate);

        TenantConfig PopulateTenantConfigs(string tenant, string fullAddress, DatabaseConfig databaseConfig, TenantConfig tenantConfig);

        byte[] ConvertIntKeyToBytesArray(int key);

    }
}
