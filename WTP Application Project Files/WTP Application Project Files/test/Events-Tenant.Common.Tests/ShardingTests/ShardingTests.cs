using System.Data.SqlClient;
using Events_Tenant.Common.Interfaces;
using Events_Tenant.Common.Utilities;
using Events_TenantUserApp.EF.CatalogDB;
using Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;

namespace Events_Tenant.Common.Tests.ShardingTests
{
    [TestClass]
    public class ShardingTests
    {
        #region Private fields

        internal const string ShardMapManagerTestConnectionString = "Data Source=localhost;Integrated Security=True;";

        private const string CreateDatabaseQuery =
            "IF EXISTS (SELECT name FROM sys.databases WHERE name = N'TestTenant') BEGIN DROP DATABASE [TestTenant] END CREATE DATABASE [TestTenant]";

        private CatalogConfig _catalogConfig;
        private DatabaseConfig _databaseConfig;
        private string _connectionString;

        private Mock<ICatalogRepository> _mockCatalogRepo;
        private Mock<ITenantRepository> _mockTenantRepo;
        private Mock<IUtilities> _mockUtilities;

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

            _connectionString = "Data Source=localhost;Initial Catalog=ShardMapManager;Integrated Security=SSPI;";

            _mockCatalogRepo = new Mock<ICatalogRepository>();
            _mockCatalogRepo.Setup(repo => repo.Add(tenant));

            _mockTenantRepo = new Mock<ITenantRepository>();

            _mockUtilities = new Mock<IUtilities>();

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
            var sharding = new Sharding(_catalogConfig.CatalogDatabase, _connectionString, _mockCatalogRepo.Object, _mockTenantRepo.Object, _mockUtilities.Object);

            Assert.IsNotNull(sharding);
            Assert.IsNotNull(sharding.ShardMapManager);
        }

        [TestMethod]
        public async void RegisterShardTest()
        {
            _databaseConfig = new DatabaseConfig
            {
                SqlProtocol = SqlProtocol.Default
            };

            var sharding = new Sharding(_catalogConfig.CatalogDatabase, _connectionString, _mockCatalogRepo.Object, _mockTenantRepo.Object, _mockUtilities.Object);
            var result = await Sharding.RegisterNewShard("TestTenant", 397858529, "localhost", _databaseConfig.DatabaseServerPort, _catalogConfig.ServicePlan);

            Assert.IsTrue(result);
        }
       
    }
}
