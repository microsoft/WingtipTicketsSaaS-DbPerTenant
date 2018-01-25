using System.Collections.Generic;
using System.Threading.Tasks;
using Events_Tenant.Common.Models;
using Events_TenantUserApp.EF.CatalogDB;

namespace Events_Tenant.Common.Interfaces
{
    public interface ICatalogRepository
    {
        Task<List<TenantModel>> GetAllTenants();
        Task<TenantModel> GetTenant(string tenantName);
        bool Add(Tenants tenant);
    }
}
