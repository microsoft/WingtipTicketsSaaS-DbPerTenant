using System;
using System.Data.SqlClient;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_TenantUserApp.EF.CatalogDB;
using Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement;
using Microsoft.Extensions.Logging;

namespace Events_Tenant.Common.Utilities
{
    /// <summary>
    /// The class which performs all tasks related to sharding
    /// </summary>
    public class Sharding
    {
        #region Private declarations
        private static IHelper _helper;
        private static ITenantsRepository _tenantsRepository;
        #endregion


        #region Public Properties

        public ShardMapManager ShardMapManager { get; }

        public static ListShardMap<int> ShardMap { get; set; }

        #endregion

        #region Constructors

        /// <summary>
        /// Initializes a new instance of the <see cref="Sharding" /> class.
        /// <para>Bootstrap Elastic Scale by creating a new shard map manager and a shard map on the shard map manager database if necessary.</para>
        /// </summary>
        /// <param name="catalogConfig">The catalog configuration.</param>
        /// <param name="databaseConfig">The database configuration.</param>
        /// <param name="tenantsRepository">The tenants repository.</param>
        /// <param name="helper">The helper.</param>
        public Sharding(CatalogConfig catalogConfig, DatabaseConfig databaseConfig, ITenantsRepository tenantsRepository, IHelper helper)
        {
            try
            {
                _tenantsRepository = tenantsRepository;
                _helper = helper;

                var smmconnstr = _helper.GetSqlConnectionString(databaseConfig, catalogConfig);

                // Deploy shard map manager
                // if shard map manager exists, refresh content, else create it, then add content
                ShardMapManager smm;
                ShardMapManager =
                    !ShardMapManagerFactory.TryGetSqlShardMapManager(smmconnstr,
                        ShardMapManagerLoadPolicy.Lazy, out smm)
                        ? ShardMapManagerFactory.CreateSqlShardMapManager(smmconnstr)
                        : smm;

                // check if shard map exists and if not, create it 
                ListShardMap<int> sm;
                ShardMap = !ShardMapManager.TryGetListShardMap(catalogConfig.CatalogDatabase, out sm)
                    ? ShardMapManager.CreateListShardMap<int>(catalogConfig.CatalogDatabase)
                    : sm;
            }
            catch (Exception ex)
            {
                // _logger.LogError(0, ex, "Error in sharding initialisation.");
                throw new ApplicationException("Error in sharding initialisation.");
            }

        }

        #endregion

        #region Public methods

        /// <summary>
        /// Registers the new shard.
        /// Verify if shard exists for the tenant. If not then create new shard and add tenant details to Tenants table in catalog
        /// </summary>
        /// <param name="tenantName">Name of the tenant.</param>
        /// <param name="tenantId">The tenant identifier.</param>
        /// <param name="tenantServerConfig">The tenant server configuration.</param>
        /// <param name="databaseConfig">The database configuration.</param>
        /// <param name="catalogConfig">The catalog configuration.</param>
        public static bool RegisterNewShard(string tenantName, int tenantId, TenantServerConfig tenantServerConfig, DatabaseConfig databaseConfig, CatalogConfig catalogConfig)
        {
            try
            {
                Shard shard;
                ShardLocation shardLocation = new ShardLocation(tenantServerConfig.TenantServer, tenantName, databaseConfig.SqlProtocol, databaseConfig.DatabaseServerPort);

                if (!ShardMap.TryGetShard(shardLocation, out shard))
                {
                    //create shard if it does not exist
                    shard = ShardMap.CreateShard(shardLocation);
                }


                // Register the mapping of the tenant to the shard in the shard map.
                // After this step, DDR on the shard map can be used
                PointMapping<int> mapping;
                if (!ShardMap.TryGetMappingForKey(tenantId, out mapping))
                {
                    var pointMapping = ShardMap.CreatePointMapping(tenantId, shard);

                    //convert from int to byte[] as tenantId has been set as byte[] in Tenants entity
                    var key = _helper.ConvertIntKeyToBytesArray(pointMapping.Value);

                    //add tenant to Tenants table
                    var tenant = new Tenants
                    {
                        ServicePlan = catalogConfig.ServicePlan,
                        TenantId = key,
                        TenantName = tenantName
                    };

                    _tenantsRepository.Add(tenant);
                }
                return true;
            }
            catch (Exception ex)
            {
                // _logger.LogError(0, ex, "Error in registering new shard.");
                //throw new ApplicationException("Error in registering new shard.");
                return false;
            }

        }


        #endregion

    }
}
