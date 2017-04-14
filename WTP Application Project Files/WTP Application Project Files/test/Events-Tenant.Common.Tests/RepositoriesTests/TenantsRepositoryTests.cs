using System;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Tests.MockRepositories;
using Events_TenantUserApp.EF.CatalogDB;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Events_Tenant.Common.Tests.RepositoriesTests
{
    [TestClass]
    public class TenantsRepositoryTests
    {
        private ITenantsRepository _tenantsRepository;

        [TestInitialize]
        public void Setup()
        {
            _tenantsRepository = new MockTenantsRepository();
            _tenantsRepository.Add(SetTenant());
        }

        [TestMethod]
        public void AddTenantTest()
        {
            var result = _tenantsRepository.Add(SetTenant());
            Assert.IsTrue(result);
        }

        [TestMethod]
        public void GetTenant()
        {
            var result = _tenantsRepository.GetTenant("tenantName");
            Assert.IsNotNull(result);
        }

        [TestMethod]
        public void GetTenants()
        {
            var result = _tenantsRepository.GetAllTenants();
            Assert.IsNotNull(result);
        }
         
        private Tenants SetTenant()
        {
          return  new Tenants
          {
              TenantId = BitConverter.GetBytes(65456464),
              TenantName = "test tenant",
              ServicePlan = "Standard"
          };

        }
    }
}
