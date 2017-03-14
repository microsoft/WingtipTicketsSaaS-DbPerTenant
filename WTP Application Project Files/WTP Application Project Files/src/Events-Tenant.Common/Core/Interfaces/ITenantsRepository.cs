using System.Collections.Generic;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;

namespace Events_Tenant.Common.Core.Interfaces
{
    public interface ITenantsRepository
    {
        IEnumerable<TenantModel> GetAllTenants(CustomerCatalogConfig customerCatalogConfig, DatabaseConfig databaseConfig);
        TenantModel GetTenant(string tenantName, CustomerCatalogConfig customerCatalogConfig, DatabaseConfig databaseConfig);
    }
}
