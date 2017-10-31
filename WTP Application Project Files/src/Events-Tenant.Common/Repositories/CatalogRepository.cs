using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Events_Tenant.Common.Interfaces;
using Events_Tenant.Common.Mapping;
using Events_Tenant.Common.Models;
using Events_TenantUserApp.EF.CatalogDB;
using Microsoft.EntityFrameworkCore;

namespace Events_Tenant.Common.Repositories
{
    public class CatalogRepository : ICatalogRepository
    {
        #region Private variables

        private readonly CatalogDbContext _catalogDbContext;

        #endregion

        #region Constructor

        public CatalogRepository(CatalogDbContext catalogDbContext)
        {
            _catalogDbContext = catalogDbContext;
        }

        #endregion

        public async Task<List<TenantModel>> GetAllTenants()
        {
            var allTenantsList = await _catalogDbContext.Tenants.ToListAsync();

            if (allTenantsList.Count > 0)
            {
                return allTenantsList.Select(tenant => tenant.ToTenantModel()).ToList();
            }

            return null;
        }

        public async Task<TenantModel> GetTenant(string tenantName)
        {
            var tenants = await _catalogDbContext.Tenants.Where(i => Regex.Replace(i.TenantName.ToLower(), @"\s+", "") == tenantName).ToListAsync();

            if (tenants.Any())
            {
                var tenant = tenants.FirstOrDefault();
                return tenant?.ToTenantModel();
            }

            return null;
        }

        public bool Add(Tenants tenant)
        {
            _catalogDbContext.Tenants.Add(tenant);
            _catalogDbContext.SaveChangesAsync();

            return true;
        }
    }
}
