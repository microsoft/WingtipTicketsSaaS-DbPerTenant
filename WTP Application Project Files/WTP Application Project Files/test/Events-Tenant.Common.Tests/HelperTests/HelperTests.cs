using System;
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
            mockCountryRepo.Setup(repo => repo.GetAllCountries("User ID=developer;Password=password;Connect Timeout=0;Application Name=EntityFramework", 12345)).Returns(GetCountries());

            var mockTenantsRepo = new Mock<ITenantsRepository>();
            mockTenantsRepo.Setup(repo => repo.GetTenant("tenant")).Returns(GetTenantModel());

            var mockVenuesRepo = new Mock<IVenuesRepository>();
            mockVenuesRepo.Setup(repo => repo.GetVenueDetails("User ID=developer;Password=password;Connect Timeout=0;Application Name=EntityFramework", 12345)).Returns(GetVenue());

            var mockVenueTypesRepo = new Mock<IVenueTypesRepository>();
            mockVenueTypesRepo.Setup(repo => repo.GetVenueType("Classic", "User ID=developer;Password=password;Connect Timeout=0;Application Name=EntityFramework", 12345)).Returns(GetVenueType());

            mockCountryRepo.Setup(repo => repo.GetCountry("USA", "User ID=developer;Password=password;Connect Timeout=0;Application Name=EntityFramework", 12345)).Returns(GetCountry());

            _helper = new Helper(mockCountryRepo.Object, mockTenantsRepo.Object, mockVenuesRepo.Object, mockVenueTypesRepo.Object);

        }

  
        [TestMethod]
        public void GetBasicSqlConnectionStringTest()
        {
            DatabaseConfig dbConfig = new DatabaseConfig
            {
                ConnectionTimeOut = 30,
                DatabasePassword = "password",
                DatabaseUser = "dbUser"
            };

            var connectionStr = _helper.GetBasicSqlConnectionString(dbConfig);

            Assert.IsNotNull(connectionStr);
            Assert.AreEqual("User ID=dbUser;Password=password;Connect Timeout=30;Application Name=EntityFramework", connectionStr);
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

            CatalogConfig catalogConfig = new CatalogConfig
            {
                CatalogDatabase = "testDatabase",
                CatalogServer = "testServer"
            };

            var connectionStr = _helper.GetSqlConnectionString(dbConfig, catalogConfig);

            Assert.IsNotNull(connectionStr);
            Assert.AreEqual("Data Source=Default:testServer,0;Initial Catalog=testDatabase;User ID=dbUser;Password=password;Connect Timeout=30;Application Name=EntityFramework", connectionStr);
        }


        [TestMethod]
        public void PopulateTenantConfigsTest()
        {
            var venueModel = new VenueModel
            {
                CountryCode = "USA",
                VenueName = "TestVenue"
            };

            var databaseConfig = new DatabaseConfig
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

            var tenantConfigs = _helper.PopulateTenantConfigs("tenant", "http://events.wtp.bg1.trafficmanager.net/contosoconcerthall", databaseConfig, tenantConfig);

            Assert.IsNotNull(tenantConfigs);
            Assert.AreEqual("$", tenantConfigs.Currency);
            Assert.AreEqual("bg1", tenantConfigs.User);
        }

        [TestMethod]
        public void GetUser()
        {
            var host = "events.wtp.bg1.trafficmanager.net";
            string[] hostpieces = host.Split(new string[] { "." }, StringSplitOptions.RemoveEmptyEntries);
            var user = hostpieces[2];

            Assert.AreEqual("bg1", user);
        }

        [TestMethod]
        public void GetUser2()
        {
            var host = "localhost:41208";
            string[] hostpieces = host.Split(new string[] { "." }, StringSplitOptions.RemoveEmptyEntries);
            var subdomain = hostpieces[0];
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

        private List<CountryModel> GetCountries()
        {
            return new List<CountryModel>
            {
                new CountryModel
                {
                    CountryCode = "USA",
                    CountryName = "United States",
                    Language = "en-US"
                },
                new CountryModel
                {
                    CountryCode = "MUR",
                    CountryName = "Mauritius",
                    Language = "en-UK"
                }
            };
        }

        private TenantModel GetTenantModel()
        {
            return new TenantModel
            {
                VenueName = "Venue 1",
                ServicePlan = "Standard",
                TenantId = 12345,
                TenantIdInString = "12345",
                TenantName = "testTenant"
            };
        }

        private VenueModel GetVenue()
        {
            return new VenueModel
            {
                VenueName = "Venue 1",
                PostalCode = "741",
                CountryCode = "USA",
                VenueType = "Classic"
            };
        }

        private VenueTypeModel GetVenueType()
        {
            return new VenueTypeModel
            {
                VenueType = "Classic",
                EventTypeName = "Classical Concert",
                Language = "en-us",
                EventTypeShortName = "Concert",
                EventTypeShortNamePlural = "Concerts",
                VenueTypeName = "Classical Music Venue"
            };
        }
        #endregion

    }
}
