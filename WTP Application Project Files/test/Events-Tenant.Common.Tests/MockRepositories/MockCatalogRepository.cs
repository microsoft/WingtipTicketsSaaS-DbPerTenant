using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Events_Tenant.Common.Interfaces;
using Events_Tenant.Common.Models;
using Events_TenantUserApp.EF.CatalogDB;

namespace Events_Tenant.Common.Tests.MockRepositories
{
    public class MockCatalogRepository : ICatalogRepository
    {
        private List<Tenants> Tenants { get; set; }

        public MockCatalogRepository()
        {
            Tenants = new List<Tenants>();
        }

        public async Task<List<TenantModel>> GetAllTenants()
        {
            return Tenants.Select(tenant => new TenantModel
            {
                TenantId = BitConverter.ToInt32(tenant.TenantId, 0),
                TenantName = tenant.TenantName,
                ServicePlan = tenant.ServicePlan
            }).ToList();
        }

        public async Task<TenantModel> GetTenant(string tenantName)
        {
            var tenant = Tenants[0];
            TenantModel tenantModel = new TenantModel
            {
                TenantId = BitConverter.ToInt32(tenant.TenantId, 0),
                TenantName = tenant.TenantName,
                ServicePlan = tenant.ServicePlan
            };
            return tenantModel;
        }

        public bool Add(Tenants tenant)
        {
            Tenants.Add(tenant);
            return true;
        }
    }
}
