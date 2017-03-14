using System;
using System.Data.Common;
using System.Data.Entity;
using System.Data.Entity.Core.EntityClient;
using System.Data.SqlClient;
using Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement;

namespace Events_TenantUserApp.EF.Models
{
    /// <summary>
    /// Partial class to override the connection string
    /// <para>The connection string contains tenant name</para>
    /// </summary>
    /// <seealso cref="DbContext" />
    public partial class TenantEntities
    {
        #region Constructors

        /// <summary>
        /// Constructor to deploy schema and migrations to a new shard
        /// </summary>
        /// <param name="connectionString">The connection string.</param>
        protected internal TenantEntities(string connectionString)
            : base(SetInitializerForConnection(connectionString))
        {
        }

        /// <summary>
        /// Constructor for data dependent routing. This call will open a validated connection routed to the proper shard by the shard map manager.
        /// Note that the base class constructor call will fail for an open connection if migrations need to be done and SQL credentials are used.
        /// This is the reason for the separation of Constructors into the DDR case (this Constructor) and the internal Constructor for new shards.
        /// </summary>
        /// <param name="shardMap">The shard map.</param>
        /// <param name="shardingKey">The sharding key.</param>
        /// <param name="connectionStr">The connection string.</param>
        /// <param name="metadataWorkSpaceConnectionString">The metadata work space connection string.</param>
        public TenantEntities(ShardMap shardMap, byte[] shardingKey, string connectionStr, string metadataWorkSpaceConnectionString)
            : base(CreateDdrConnection(shardMap, shardingKey, connectionStr, metadataWorkSpaceConnectionString) , true)
        {
        }

        #endregion

        #region Private methods

        /// <summary>
        /// Only static methods are allowed in calls into base class constructors
        /// </summary>
        /// <param name="connnectionString">The connnection string.</param>
        /// <returns></returns>
        private static string SetInitializerForConnection(string connnectionString)
        {
            //create database if it does not exist
            Database.SetInitializer<TenantEntities>(new CreateDatabaseIfNotExists<TenantEntities>());
            return connnectionString;
        }

        /// <summary>
        /// Creates the DDR (Data Dependent Routing) connection.
        /// Only static methods are allowed in calls into base class constructors
        /// </summary>
        /// <param name="shardMap">The shard map.</param>
        /// <param name="shardingKey">The sharding key.</param>
        /// <param name="connectionStr">The connection string.</param>
        /// <param name="metadataWorkSpaceConnectionString">The metadata work space connection string.</param>
        /// <returns></returns>
        private static DbConnection CreateDdrConnection(ShardMap shardMap, byte[] shardingKey, string connectionStr, string metadataWorkSpaceConnectionString)
        {
            // No initialization
            Database.SetInitializer<TenantEntities>(null);

            //convert key from byte[] to int as OpenConnectionForKey requires int
            int key = BitConverter.ToInt32(shardingKey, 0);

            // Ask shard map to broker a validated connection for the given key
            SqlConnection sqlConn = shardMap.OpenConnectionForKey(key, connectionStr);
            
            //convert into Entity Connection since we are using EF
            var efConnection = new EntityConnection(metadataWorkSpaceConnectionString);

            // Create Entity connection that holds the sharded SqlConnection and metadata workspace
            var workspace = efConnection.GetMetadataWorkspace();
            var entCon = new EntityConnection(workspace, sqlConn, true);
            
            return entCon;
        }


        #endregion


    }
}
