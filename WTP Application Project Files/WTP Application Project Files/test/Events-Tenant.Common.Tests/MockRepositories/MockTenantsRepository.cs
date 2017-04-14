using System;
using System.Collections.Generic;
using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;
using Events_TenantUserApp.EF.CatalogDB;

namespace Events_Tenant.Common.Tests.MockRepositories
{
    public class MockTenantsRepository : ITenantsRepository
    {
        private List<Tenants> tenants { get; set; }

        public MockTenantsRepository()
        {
            tenants = new List<Tenants>();
        }

        public List<TenantModel> GetAllTenants()
        {
            return tenants.Select(tenant => new TenantModel
            {
                TenantId = BitConverter.ToInt32(tenant.TenantId, 0),
                TenantName = tenant.TenantName,
                ServicePlan = tenant.ServicePlan
            }).ToList();
        }

        public TenantModel GetTenant(string tenantName)
        {
            var tenant = tenants[0];
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
            tenants.Add(tenant);
            return true;
        }
    }
}
