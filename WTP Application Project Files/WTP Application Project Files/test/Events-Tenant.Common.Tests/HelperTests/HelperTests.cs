using System.Collections.Generic;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;

namespace Events_Tenant.Common.Tests.HelperTests
{
    [TestClass]
    public class HelperTests
    {
        private Helper _helper;

        [TestInitialize]
        public void Setup()
        {
            var mockCountryRepo = new Mock<ICountryRepository>();

            mockCountryRepo.Setup(repo => repo.GetCountry("USA", "User ID=developer;Password=password;Connect Timeout=0;Application Name=EntityFramework", 1368421345)).Returns(GetCountry());

            _helper = new Helper(mockCountryRepo.Object);

        }

        [TestMethod]
        public void GetTenantKeyTest()
        {
            var key = _helper.GetTenantKey("contoso");

            Assert.IsNotNull(key);
            Assert.AreEqual(-1136926586, key);
        }

        [TestMethod]
        public void GetSqlConnectionStringTest()
        {
            DatabaseConfig dbConfig = new DatabaseConfig
            {
                ConnectionTimeOut = 30,
                DatabasePassword = "password",
                DatabaseUser = "dbUser"
            };

            var connectionStr = _helper.GetSqlConnectionString(dbConfig);

            Assert.IsNotNull(connectionStr);
            Assert.AreEqual("User ID=dbUser;Password=password;Connect Timeout=30;Application Name=EntityFramework", connectionStr);
        }


        [TestMethod]
        public void PopulateTenantConfigsTest()
        {
            var venueModel = new VenueModel
            {
                CountryCode = "USA",
                VenueName = "TestVenue"
            };

            var databaseCOnfig = new DatabaseConfig
            {
                DatabasePassword = "password",
                DatabaseUser = "developer"
            };

            var tenantConfig = new TenantConfig
            {
                BlobPath = "testPath"
            };

            var venueTypeModel = new VenueTypeModel
            {
                EventTypeShortNamePlural = "shortName",
                VenueType = "pop",
                Language = "en-us"
            };

            var tenantModel = new TenantModel
            {
                TenantId = 1368421345
            };

            var countries = new List<CountryModel>
            {
                new CountryModel
                {
                    Language = "en-us",
                    CountryCode = "USA",
                    CountryName = "United States"
                }
            };

            var tenantConfigs = _helper.PopulateTenantConfigs("tenant", tenantConfig, databaseCOnfig, venueModel,
                venueTypeModel, tenantModel, countries);

            Assert.IsNotNull(tenantConfigs);
            Assert.AreEqual("$", tenantConfigs.Currency);
        }

        #region Private methods

        private CountryModel GetCountry()
        {
            return new CountryModel
            {
                Language = "en-us",
                CountryCode = "USA",
                CountryName = "United States"
            }; 
        }

        #endregion

    }
}
