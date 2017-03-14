using System.Collections.Generic;
using System.Data;
using System.Data.Entity.Core.EntityClient;
using System.Data.SqlClient;
using System.Security.Cryptography;
using System.Text;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Core.Repositories;
using Events_Tenant.Common.Utilities;
using Events_TenantUserApp.EF.Models;

namespace Events_Tenant.Common.Helpers
{
    /// <summary>
    /// Helper class 
    /// </summary>
    public class Helper
    {

        #region Get Connection strings

        /// <summary>
        /// Gets the customer catalog connection string using the app settings
        /// </summary>
        /// <param name="customerCatalogConfig">The customer catalog configuration.</param>
        /// <param name="databaseConfig">The database configuration.</param>
        /// <returns></returns>
        public static string GetCustomerCatalogConnectionString(CustomerCatalogConfig customerCatalogConfig, DatabaseConfig databaseConfig)
        {
            return
                $"metadata=res://*/Models.CustomerCatalogModel.csdl|res://*/Models.CustomerCatalogModel.ssdl|res://*/Models.CustomerCatalogModel.msl;provider=System.Data.SqlClient;provider connection string='data source=tcp:{customerCatalogConfig.CustomerCatalogServer},1433;initial catalog={customerCatalogConfig.CustomerCatalogDatabase};persist security info=True;user id={databaseConfig.DatabaseUser};password={databaseConfig.DatabasePassword};MultipleActiveResultSets=True;App=EntityFramework'";

        }

        /// <summary>
        /// Gets the tenant connection string using the tenant name
        /// </summary>
        /// <param name="databaseConfig">The database configuration.</param>
        /// <param name="tenantServerConfig">The tenant server configuration.</param>
        /// <returns></returns>
        public static string GetTenantConnectionString(DatabaseConfig databaseConfig, TenantServerConfig tenantServerConfig)
        {
            var connectionString = BuildTenantConnectionString(tenantServerConfig.TenantServer,
               databaseConfig.DatabaseUser, databaseConfig.DatabasePassword);

            return connectionString;
        }

        /// <summary>
        /// Gets the sql connection string.
        /// </summary>
        /// <param name="databaseConfig">The database configuration.</param>
        /// <returns></returns>
        public static string GetSqlConnectionString(DatabaseConfig databaseConfig)
        {
            var connStrBldr = new SqlConnectionStringBuilder
            {
                UserID = databaseConfig.DatabaseUser,
                Password = databaseConfig.DatabasePassword,
                ApplicationName = "EntityFramework"
            };

            return connStrBldr.ConnectionString;
        }


        /// <summary>
        /// Builds the tenant connection string.
        /// </summary>
        /// <param name="databaseServer">The database server.</param>
        /// <param name="username">The database username.</param>
        /// <param name="password">The database password.</param>
        /// <returns></returns>
        private static string BuildTenantConnectionString(string databaseServer, string username, string password)
        {
            return
                $"metadata=res://*/Models.TenantModel.csdl|res://*/Models.TenantModel.ssdl|res://*/Models.TenantModel.msl;provider=System.Data.SqlClient;provider connection string='data source=tcp:{databaseServer},1433;initial catalog=;persist security info=True;user id={username};password={password};MultipleActiveResultSets=True;App=EntityFramework'";
        }


        #endregion

        #region Public methods

        /// <summary>
        /// Generates the tenant Id using MD5 Hashing.
        /// </summary>
        /// <param name="tenantName">Name of the tenant.</param>
        /// <returns></returns>
        public static byte[] GetTenantKey(string tenantName)
        //public static int GetTenantKey(string tenantName)
        {
            var normalizedTenantName = tenantName.Replace(" ", string.Empty).ToLower();

            //Produce utf8 encoding of tenant name 
            var tenantNameBytes = Encoding.UTF8.GetBytes(normalizedTenantName);

            //Produce the md5 hash which reduces the size
            MD5 md5 = MD5.Create();
            var tenantHashBytes = md5.ComputeHash(tenantNameBytes);

            //Convert to integer for use as the key in the catalog 
            // int tenantKey = BitConverter.ToInt32(tenantHashBytes, 0);

            return tenantHashBytes;

        }

        /// <summary>
        /// Resets all tenants' event dates.
        /// </summary>
        /// <param name="tenantServerConfig">The tenant server configuration.</param>
        /// <param name="databaseConfig">The database configuration.</param>
        /// <param name="customerCatalogConfig">The customer catalog configuration.</param>
        public static void ResetTenantEventDates(TenantServerConfig tenantServerConfig, DatabaseConfig databaseConfig, CustomerCatalogConfig customerCatalogConfig)
        {
            ITenantsRepository tenantsRepository = new TenantsRepository();

            var connectionString = GetSqlConnectionString(databaseConfig);

            var tenants = tenantsRepository.GetAllTenants(customerCatalogConfig, databaseConfig);

            foreach (var tenant in tenants)
            {
                using (var context = new TenantEntities(Sharding.ShardMap, tenant.TenantId, connectionString, GetTenantConnectionString(databaseConfig, tenantServerConfig)))
                {
                    context.Database.ExecuteSqlCommand("sp_ResetEventDates");
                }
            }
        }

        #endregion

    }
}
