using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Events_Tenant.Common.Interfaces;
using Events_Tenant.Common.Mapping;
using Events_Tenant.Common.Models;
using Events_TenantUserApp.EF.CatalogDB;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using System;

namespace Events_Tenant.Common.Repositories
{
    public class CatalogRepository : ICatalogRepository
    {
        #region Private variables

        private readonly CatalogDbContext _catalogDbContext;
        private readonly IConfiguration _configuration;

        #endregion

        #region Constructor

        public CatalogRepository(CatalogDbContext catalogDbContext, IConfiguration configuration)
        {
            _catalogDbContext = catalogDbContext;
            _configuration = configuration;
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
            var wingtipUser = _configuration["User"];
            var tenantServerName = "tenants1-dpt-" + wingtipUser + "-home";
            var normalizedTenantName = tenant.TenantName.Replace(" ", string.Empty).ToLower();
            var location = _configuration["APP_REGION"];
            var defaultTenantValues = _configuration.GetSection("DefaultEnvironment");

            //Add tenant to tenants table
            _catalogDbContext.Tenants.Add(tenant);

            //Add tenant database resources to catalog
            var tenantDatabase = new Databases
            {
                ServerName = tenantServerName,
                DatabaseName = normalizedTenantName,
                ServiceObjective = defaultTenantValues["DatabaseServiceObjective"],
                ElasticPoolName = defaultTenantValues["ElasticPoolName"],
                State = "created",
                RecoveryState = "n/a",
                LastUpdated = System.DateTime.Now
            };
            var databaseExists = (from a in _catalogDbContext.Databases where a.DatabaseName == tenantDatabase.DatabaseName && a.ServerName == tenantDatabase.ServerName select a);
            
            if (databaseExists.FirstOrDefault() == null)
            {
                _catalogDbContext.Databases.Add(tenantDatabase);
            }
                       

            //Add tenant elastic pool resources to catalog
            var tenantElasticPool = new ElasticPools
            {
                ServerName = tenantServerName,
                ElasticPoolName = defaultTenantValues["ElasticPoolName"],
                Dtu = Int32.Parse(defaultTenantValues["ElasticPoolDTU"]),
                Edition = defaultTenantValues["ElasticPoolEdition"],
                DatabaseDtuMax = Int32.Parse(defaultTenantValues["ElasticPoolDatabaseDtuMax"]),
                DatabaseDtuMin = Int32.Parse(defaultTenantValues["ElasticPoolDatabaseDtuMin"]),
                StorageMB = Int32.Parse(defaultTenantValues["ElasticPoolStorageMB"]),
                State = "created",
                RecoveryState = "n/a",
                LastUpdated = System.DateTime.Now
            };
            var poolExists = (from a in _catalogDbContext.ElasticPools where a.ElasticPoolName == tenantElasticPool.ElasticPoolName && a.ServerName == tenantElasticPool.ServerName select a);

            if (poolExists.FirstOrDefault() == null)
            {
                _catalogDbContext.ElasticPools.Add(tenantElasticPool);
            }
            

            //Add tenant server resources to catalog
            var tenantServer = new Servers
            {
                ServerName = tenantServerName,
                Location = location,
                State = "created",
                RecoveryState = "n/a",
                LastUpdated = System.DateTime.Now
            };
            var serverExists = (from a in _catalogDbContext.Servers where a.ServerName == tenantServer.ServerName select a);

            if (serverExists.FirstOrDefault() == null)
            {
                _catalogDbContext.Servers.Add(tenantServer);
            }            

            _catalogDbContext.SaveChangesAsync();
            return true;
        }
    }
}
