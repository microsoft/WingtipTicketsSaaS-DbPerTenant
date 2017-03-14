using System;
using System.Data.SqlClient;
using Events_Tenant.Common.Helpers;
using Events_TenantUserApp.EF.Models;
using Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement;

namespace Events_Tenant.Common.Utilities
{
    /// <summary>
    /// The class which performs all tasks related to sharding
    /// </summary>
    public class Sharding
    {
        #region Public Properties

        public ShardMapManager ShardMapManager { get; }

        public static ListShardMap<int> ShardMap { get; set; }

        #endregion

        #region Constructor
        /// <summary>
        /// Initializes a new instance of the <see cref="Sharding" /> class.
        /// <para>Bootstrap Elastic Scale by creating a new shard map manager and a shard map on the shard map manager database if necessary.</para>
        /// </summary>
        /// <param name="smmconnstr">The smmconnstr.</param>
        /// <param name="customerCatalogConfig">The customer catalog configuration.</param>
        /// <param name="databaseConfig">The database configuration.</param>
        public Sharding(string smmconnstr, CustomerCatalogConfig customerCatalogConfig, DatabaseConfig databaseConfig)
        {
            // Connection string with administrative credentials for the root database
            SqlConnectionStringBuilder connStrBldr = new SqlConnectionStringBuilder(smmconnstr)
            {
                DataSource = databaseConfig.SqlProtocol + ":" + customerCatalogConfig.CustomerCatalogServer + "," + databaseConfig.DatabaseServerPort,
                InitialCatalog = customerCatalogConfig.CustomerCatalogDatabase,
                ConnectTimeout = databaseConfig.ConnectionTimeOut
            };

            // Deploy shard map manager
            // if shard map manager exists, refresh content, else create it, then add content
            ShardMapManager smm;
            ShardMapManager = !ShardMapManagerFactory.TryGetSqlShardMapManager(connStrBldr.ConnectionString, ShardMapManagerLoadPolicy.Lazy, out smm) ? ShardMapManagerFactory.CreateSqlShardMapManager(connStrBldr.ConnectionString) : smm;

            // check if shard map exists and if not, create it 
            ListShardMap<int> sm;
            ShardMap = !ShardMapManager.TryGetListShardMap(customerCatalogConfig.CustomerCatalogServer, out sm) ? ShardMapManager.CreateListShardMap<int>(customerCatalogConfig.CustomerCatalogServer) : sm;
        }

        #endregion

        #region Public methods

        /// <summary>
        /// Registers the new shard.
        /// Verify if shard exists for the tenant. If not then create new shard and add tenant details to Tenants table in customerCatalog
        /// </summary>
        /// <param name="database">The tenant database.</param>
        /// <param name="tenantId">The tenant identifier.</param>
        /// <param name="tenantServerConfig">The tenant server configuration.</param>
        /// <param name="databaseConfig">The database configuration.</param>
        /// <param name="customerCatalogConfig">The customer catalog configuration.</param>
        public void RegisterNewShard(string database, byte[] tenantId, TenantServerConfig tenantServerConfig, DatabaseConfig databaseConfig, CustomerCatalogConfig customerCatalogConfig)
        {
            Shard shard;
            ShardLocation shardLocation = new ShardLocation(tenantServerConfig.TenantServer, database, SqlProtocol.Tcp, databaseConfig.DatabaseServerPort);

            if (!ShardMap.TryGetShard(shardLocation, out shard))
            {
                //create shard if it does not exist
                shard = ShardMap.CreateShard(shardLocation);

                //add tenant to Tenants table
                using (var context = new CustomerCatalogEntities(Helper.GetCustomerCatalogConnectionString(customerCatalogConfig, databaseConfig)))
                {
                    var tenant = new Tenants
                    {
                        ServicePlan = customerCatalogConfig.ServicePlan,
                        TenantId = tenantId,
                        TenantName = database
                    };

                    context.Tenants.Add(tenant);
                    context.SaveChanges();
                }
            }


            // Register the mapping of the tenant to the shard in the shard map.
            // After this step, DDR on the shard map can be used
            PointMapping<int> mapping;
            //if (!ShardMap.TryGetMappingForKey(tenantId, out mapping))
            //{
            //    ShardMap.CreatePointMapping(tenantId, shard);
            //}

            //todo: remove and uncomment above code after TenantId has been changed to int in database
            int tenantKey = BitConverter.ToInt32(tenantId, 0);
            if (!ShardMap.TryGetMappingForKey(tenantKey, out mapping))
            {
                ShardMap.CreatePointMapping(tenantKey, shard);
            }
        }


        #endregion

    }
}
