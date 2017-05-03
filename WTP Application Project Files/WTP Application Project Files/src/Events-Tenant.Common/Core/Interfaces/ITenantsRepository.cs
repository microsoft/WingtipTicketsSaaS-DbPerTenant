using System.Collections.Generic;
using Events_Tenant.Common.Models;
using Events_TenantUserApp.EF.CatalogDB;

namespace Events_Tenant.Common.Core.Interfaces
{
    public interface ITenantsRepository
    {
        List<TenantModel> GetAllTenants();
        TenantModel GetTenant(string tenantName);
        bool Add(Tenants tenant);
    }
}
