using System;
using System.Collections.Generic;
using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;
using Events_TenantUserApp.EF.CatalogDB;

namespace Events_Tenant.Common.Core.Repositories
{
    public class TenantsRepository : ITenantsRepository
    {
        private readonly CatalogDbContext _catalogDbContext;

        public TenantsRepository(CatalogDbContext catalogDbContext)
        {
            _catalogDbContext = catalogDbContext;
        }

        public List<TenantModel> GetAllTenants()
        {
            var allTenantsList = _catalogDbContext.Tenants;
            
            return allTenantsList.Select(tenant => new TenantModel
            {
                ServicePlan = tenant.ServicePlan,
                TenantId = BitConverter.ToInt32(tenant.TenantId, 0),
                TenantName = tenant.TenantName
            }).ToList();
        }


        public TenantModel GetTenant(string tenantName)
        {
            var tenants = _catalogDbContext.Tenants.Where(i => i.TenantName == tenantName);

            if (tenants.Any())
            {
                var tenant = tenants.FirstOrDefault();

                string s2 = BitConverter.ToString(tenant.TenantId);
                s2 = s2.Replace("-", "");

                return new TenantModel
                {
                    ServicePlan = tenant.ServicePlan,
                    TenantName = tenant.TenantName,
                    TenantId = BitConverter.ToInt32(tenant.TenantId, 0),
                    TenantIdInString = s2
                };
            }

            return null;
        }

        public bool Add(Tenants tenant)
        {
            _catalogDbContext.Tenants.Add(tenant);
            _catalogDbContext.SaveChanges();

            return true;
        }

    }
}
