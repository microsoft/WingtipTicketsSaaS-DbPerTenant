using System;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Utilities;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;
using System.Data.SqlClient;
using System.Security.Cryptography;
using System.Text;
using Events_TenantUserApp.EF.CatalogDB;
using Microsoft.Azure.SqlDatabase.ElasticScale;
using Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement;

namespace Events_Tenant.Common.Tests.ShardingTests
{
    [TestClass]
    public class ShardingTests
    {
        #region Private fields

        internal const string ShardMapManagerTestConnectionString = "Data Source=localhost;Integrated Security=True;";

        private const string ShardMapManagerConnString =
            "Data Source=localhost;Initial Catalog=ShardMapManager;Integrated Security=SSPI;";

        private const string CreateDatabaseQuery =
            "IF EXISTS (SELECT name FROM sys.databases WHERE name = N'TestTenant') BEGIN DROP DATABASE [TestTenant] END CREATE DATABASE [TestTenant]";

        private CatalogConfig _catalogConfig;
        private DatabaseConfig _databaseConfig;

        private Mock<ITenantsRepository> _mockTenantsRepo;
        private Mock<IHelper> _mockHelper;

        #endregion


        [TestInitialize]
        public void Setup()
        {
            _catalogConfig = new CatalogConfig
            {
                ServicePlan = "Standard",
                CatalogDatabase = "ShardMapManager",
                CatalogServer = "localhost"
            };

            _databaseConfig = new DatabaseConfig
            {
                DatabasePassword = "",
                DatabaseUser = "",
                ConnectionTimeOut = 30,
                DatabaseServerPort = 1433,
                LearnHowFooterUrl = "",
                SqlProtocol = SqlProtocol.Tcp
            };

            var tenant = new Tenants
            {
                ServicePlan = "Standard",
                TenantName = "TestTenant",
                TenantId = new byte[0]
            };


            _mockTenantsRepo = new Mock<ITenantsRepository>();
            _mockTenantsRepo.Setup(repo => repo.Add(tenant));

            _mockHelper = new Mock<IHelper>();
            _mockHelper.Setup(helper => helper.GetSqlConnectionString(_databaseConfig, _catalogConfig)).Returns(ShardMapManagerConnString);

            #region Create tenant database on localhost

            // Clear all connection pools.
            SqlConnection.ClearAllPools();

            using (SqlConnection conn = new SqlConnection(ShardMapManagerTestConnectionString))
            {
                conn.Open();

                // Create ShardMapManager database
                using (SqlCommand cmd = new SqlCommand(CreateDatabaseQuery, conn))
                {
                    cmd.ExecuteNonQuery();
                }
            }
            #endregion

        }


        [TestMethod]
        public void ShardingTest()
        {
            var sharding = new Sharding(_catalogConfig, _databaseConfig, _mockTenantsRepo.Object, _mockHelper.Object);

            Assert.IsNotNull(sharding);
            Assert.IsNotNull(sharding.ShardMapManager);
        }

        [TestMethod]
        public void RegisterShardTest()
        {
            TenantServerConfig tenantServerConfig = new TenantServerConfig
            {
                TenantServer = "localhost"
            };

            _databaseConfig = new DatabaseConfig
            {
                SqlProtocol = SqlProtocol.Default
            };
            _mockHelper.Setup(helper => helper.GetSqlConnectionString(_databaseConfig, _catalogConfig)).Returns(ShardMapManagerConnString);

            var sharding = new Sharding(_catalogConfig, _databaseConfig, _mockTenantsRepo.Object, _mockHelper.Object);
            var result = Sharding.RegisterNewShard("TestTenant", 397858529, tenantServerConfig, _databaseConfig, _catalogConfig);

            Assert.IsTrue(result);
        }
       
    }
}
