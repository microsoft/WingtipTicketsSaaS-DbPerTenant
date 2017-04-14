using System.Collections.Generic;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;

namespace Events_Tenant.Common.Helpers
{
    public interface IHelper
    {
        string GetSqlConnectionString(DatabaseConfig databaseConfig);
        int GetTenantKey(string tenantName);

        void RegisterTenantShard(TenantServerConfig tenantServerConfig, DatabaseConfig databaseConfig, CatalogConfig catalogConfig, bool resetEventDate);

        TenantConfig PopulateTenantConfigs(string tenant, TenantConfig tenantConfig, DatabaseConfig database, VenueModel venueModel, VenueTypeModel venueTypeModel, TenantModel tenantModel, List<CountryModel> countries);
    }
}
