using System;
using Events_Tenant.Common.Interfaces;
using Events_Tenant.Common.Tests.MockRepositories;
using Events_TenantUserApp.EF.CatalogDB;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Events_Tenant.Common.Tests.RepositoriesTests
{
    [TestClass]
    public class CatalogRepositoryTests
    {
        private ICatalogRepository _catalogRepository;

        [TestInitialize]
        public void Setup()
        {
            _catalogRepository = new MockCatalogRepository();
            _catalogRepository.Add(SetTenant());
        }

        [TestMethod]
        public void AddTenantTest()
        {
            var result = _catalogRepository.Add(SetTenant());
            Assert.IsTrue(result);
        }

        [TestMethod]
        public void GetTenant()
        {
            var result = _catalogRepository.GetTenant("tenantName");
            Assert.IsNotNull(result);
        }

        [TestMethod]
        public void GetTenants()
        {
            var result = _catalogRepository.GetAllTenants();
            Assert.IsNotNull(result);
        }

        private Tenants SetTenant()
        {
            return new Tenants
            {
                TenantId = BitConverter.GetBytes(65456464),
                TenantName = "test tenant",
                ServicePlan = "Standard"
            };

        }
    }
}
