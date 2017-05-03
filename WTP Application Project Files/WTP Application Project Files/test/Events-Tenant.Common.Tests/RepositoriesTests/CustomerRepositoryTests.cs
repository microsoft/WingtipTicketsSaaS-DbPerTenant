using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Tests.MockRepositories;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Events_Tenant.Common.Tests.RepositoriesTests
{
    [TestClass]
    public class CustomerRepositoryTests
    {
        private ICustomerRepository _customerRepository;
        private string _connectionString;
        private int _tenantId;

        [TestInitialize]
        public void Setup()
        {
            _customerRepository = new MockCustomerRepository();
            _connectionString = "User ID=developer;Password=password;Connect Timeout=0;Application Name=EntityFramework";
            _tenantId = 1368421345;

            _customerRepository.Add(CreateCustomerModel(), _connectionString, _tenantId);
        }

        [TestMethod]
        public void AddCustomerTest()
        {
            var result = _customerRepository.Add(CreateCustomerModel(), _connectionString, _tenantId);

            Assert.AreEqual(123, result);
        }

        [TestMethod]
        public void GetCustomerTest()
        {
            var result = _customerRepository.GetCustomer("test@email.com", _connectionString, _tenantId);

            Assert.IsNotNull(result);
            Assert.AreEqual("USA", result.CountryCode);
            Assert.AreEqual("test@email.com", result.Email);
            Assert.AreEqual(123, result.CustomerId);
            Assert.AreEqual("12345", result.PostalCode);
            Assert.AreEqual("last name", result.LastName);
            Assert.AreEqual("first name", result.FirstName);
            Assert.AreEqual("pass", result.Password);

        }


        private CustomerModel CreateCustomerModel()
        {
            return new CustomerModel
            {
                CountryCode = "USA",
                Email = "test@email.com",
                CustomerId = 123,
                PostalCode = "12345",
                LastName = "last name",
                FirstName = "first name",
                Password = "pass"
            };
        }

    }
}
