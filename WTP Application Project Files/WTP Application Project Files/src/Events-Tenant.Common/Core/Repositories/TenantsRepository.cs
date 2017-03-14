using System.Collections.Generic;
using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;
using Events_TenantUserApp.EF.Models;

namespace Events_Tenant.Common.Core.Repositories
{
    public class TenantsRepository : ITenantsRepository
    {
        public IEnumerable<TenantModel> GetAllTenants(CustomerCatalogConfig customerCatalogConfig, DatabaseConfig databaseConfig)
        {
            string connectionString = Helper.GetCustomerCatalogConnectionString(customerCatalogConfig, databaseConfig);

            using (var context = new CustomerCatalogEntities(connectionString))
            {
                var allTenantsList = context.Tenants.AsEnumerable();
                
                return allTenantsList.Select(tenant => new TenantModel
                {
                    ServicePlan = tenant.ServicePlan,
                    TenantId = tenant.TenantId,
                    TenantName = tenant.TenantName
                }).ToList();
            }
        }


        public TenantModel GetTenant(string tenantName, CustomerCatalogConfig customerCatalogConfig, DatabaseConfig databaseConfig)
        {
            string connectionString = Helper.GetCustomerCatalogConnectionString(customerCatalogConfig, databaseConfig);

            using (var context = new CustomerCatalogEntities(connectionString))
            {
                var tenant = context.Tenants.First(i => i.TenantName == tenantName);

                var tenantModel = new TenantModel
                {
                    ServicePlan = tenant.ServicePlan,
                    TenantName = tenant.TenantName,
                    TenantId = tenant.TenantId
                };

                return tenantModel;
            }

        }
    }
}
