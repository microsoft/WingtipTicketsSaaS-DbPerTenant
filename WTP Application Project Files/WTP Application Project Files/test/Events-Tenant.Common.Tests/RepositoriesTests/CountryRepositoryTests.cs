using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Tests.MockRepositories;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Events_Tenant.Common.Tests.RepositoriesTests
{
    [TestClass]
    public class CountryRepositoryTests
    {
        private ICountryRepository _countryRepository;
        private  string _connectionString;
        private  int _tenantId;

        [TestInitialize]
        public void Setup()
        {
            _countryRepository = new MockCountryRepository();
            _connectionString = "User ID=developer;Password=password;Connect Timeout=0;Application Name=EntityFramework";
            _tenantId = 1368421345;
        }

        [TestMethod]
        public void GetAllCountriesTest()
        {
            var result = _countryRepository.GetAllCountries(_connectionString, _tenantId);

            Assert.IsNotNull(result);
            Assert.AreEqual(1, result.Count);
            Assert.AreEqual("en-us", result[0].Language);
            Assert.AreEqual("USA", result[0].CountryCode);
            Assert.AreEqual("United States", result[0].CountryName);
        }

        [TestMethod]
        public void GetGetCountryTest()
        {
            var result = _countryRepository.GetCountry("USA", _connectionString, _tenantId);

            Assert.IsNotNull(result);
            Assert.AreEqual("en-us", result.Language);
            Assert.AreEqual("USA", result.CountryCode);
            Assert.AreEqual("United States", result.CountryName);
        }
    }
}
