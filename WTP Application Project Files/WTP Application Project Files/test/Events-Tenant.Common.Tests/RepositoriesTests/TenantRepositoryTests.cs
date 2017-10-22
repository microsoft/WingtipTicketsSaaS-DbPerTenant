using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Events_Tenant.Common.Interfaces;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Tests.MockRepositories;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Events_Tenant.Common.Tests.RepositoriesTests
{
    [TestClass]
    public class TenantRepositoryTests
    {
        private ITenantRepository _tenantRepository;
        private const int _tenantId = 1368421345;
        private const int _numberOfTicketPurchases = 1;
        private const int _ticketsSold = 1;

        [TestInitialize]
        public void Setup()
        {
            _tenantRepository = new MockTenantRepository();
            _tenantRepository.AddCustomer(CreateCustomerModel(), _tenantId);
        }

        [TestMethod]
        public async Task GetAllCountriesTest()
        {
            var result = (await _tenantRepository.GetAllCountries(_tenantId));

            Assert.IsNotNull(result);
            Assert.AreEqual(1, result.Count);
            Assert.AreEqual("en-us", result[0].Language);
            Assert.AreEqual("USA", result[0].CountryCode);
            Assert.AreEqual("United States", result[0].CountryName);
        }

        [TestMethod]
        public async Task GetGetCountryTest()
        {
            var result = await _tenantRepository.GetCountry("USA", _tenantId);

            Assert.IsNotNull(result);
            Assert.AreEqual("en-us", result.Language);
            Assert.AreEqual("USA", result.CountryCode);
            Assert.AreEqual("United States", result.CountryName);
        }

        [TestMethod]
        public void AddCustomerTest()
        {
            var result = (_tenantRepository.AddCustomer(CreateCustomerModel(), _tenantId)).Result;

            Assert.AreEqual(123, result);
        }

        [TestMethod]
        public async Task GetCustomerTest()
        {
            var result = await _tenantRepository.GetCustomer("test@email.com", _tenantId);

            Assert.IsNotNull(result);
            Assert.AreEqual("USA", result.CountryCode);
            Assert.AreEqual("test@email.com", result.Email);
            Assert.AreEqual(123, result.CustomerId);
            Assert.AreEqual("12345", result.PostalCode);
            Assert.AreEqual("last name", result.LastName);
            Assert.AreEqual("first name", result.FirstName);
            Assert.AreEqual("pass", result.Password);

        }

        [TestMethod]
        public async Task GetEventSectionsTest()
        {
            var result = await _tenantRepository.GetEventSections(1, _tenantId);

            Assert.IsNotNull(result);
            Assert.AreEqual(3, result.Count);
            Assert.AreEqual(1, result[0].SectionId);
            Assert.AreEqual(1, result[0].EventId);
            Assert.AreEqual(100, result[0].Price);
            Assert.AreEqual(2, result[1].SectionId);
            Assert.AreEqual(1, result[1].EventId);
            Assert.AreEqual(80, result[1].Price);
            Assert.AreEqual(3, result[2].SectionId);
            Assert.AreEqual(1, result[2].EventId);
            Assert.AreEqual(60, result[2].Price);
        }

        [TestMethod]
        public async Task GetEventsForTenantTest()
        {
            var result = await _tenantRepository.GetEventsForTenant(_tenantId);
            Assert.IsNotNull(result);
            Assert.AreEqual(2, result.Count);
            Assert.AreEqual(1, result[0].EventId);
            Assert.AreEqual("Event 1", result[0].EventName);
            Assert.AreEqual("Event 1 Subtitle", result[0].SubTitle);
            Assert.AreEqual(2, result[1].EventId);
            Assert.AreEqual("Event 2", result[1].EventName);
            Assert.AreEqual("Event 2 Subtitle", result[1].SubTitle);
        }

        [TestMethod]
        public async Task GetEventTest()
        {
            var result = await _tenantRepository.GetEvent(1, _tenantId);

            Assert.IsNotNull(result);
            Assert.AreEqual(1, result.EventId);
            Assert.AreEqual("Event 1", result.EventName);
            Assert.AreEqual("Event 1 Subtitle", result.SubTitle);
        }

        [TestMethod]
        public async Task GetSectionsTest()
        {
            List<int> sectionIds = new List<int> { 1, 2 };

            var result = await _tenantRepository.GetSections(sectionIds, _tenantId);
            Assert.IsNotNull(result);
            Assert.AreEqual(2, result.Count);
            Assert.AreEqual(1, result[0].SectionId);
            Assert.AreEqual(10, result[0].SeatsPerRow);
            Assert.AreEqual("section 1", result[0].SectionName);
            Assert.AreEqual(100, result[0].StandardPrice);
            Assert.AreEqual(4, result[0].SeatRows);

            Assert.AreEqual(2, result[1].SectionId);
            Assert.AreEqual(20, result[1].SeatsPerRow);
            Assert.AreEqual("section 2", result[1].SectionName);
            Assert.AreEqual(80, result[1].StandardPrice);
            Assert.AreEqual(5, result[1].SeatRows);

        }

        [TestMethod]
        public async Task GetSectionTest()
        {
            var result = await _tenantRepository.GetSection(1, _tenantId);
            Assert.IsNotNull(result);
            Assert.AreEqual(1, result.SectionId);
            Assert.AreEqual(10, result.SeatsPerRow);
            Assert.AreEqual("section 1", result.SectionName);
            Assert.AreEqual(100, result.StandardPrice);
            Assert.AreEqual(4, result.SeatRows);
        }

        [TestMethod]
        public void AddTicketPurchaseTest()
        {
            var ticketPurchaseModel = new TicketPurchaseModel
            {
                PurchaseDate = DateTime.Now,
                TicketPurchaseId = 12,
                CustomerId = 6,
                PurchaseTotal = 5
            };

            var result = (_tenantRepository.AddTicketPurchase(ticketPurchaseModel, _tenantId)).Result;

            Assert.IsNotNull(result);
            Assert.AreEqual(_numberOfTicketPurchases, 1);
            Assert.AreEqual(12, result);
        }

        [TestMethod]
        public async Task AddTicketTest()
        {
            var ticketModel = new TicketModel
            {
                SectionId = 2,
                EventId = 4,
                TicketPurchaseId = 50,
                SeatNumber = 41,
                RowNumber = 22,
                TicketId = 100
            };
            List<TicketModel> ticketModels = new List<TicketModel>();
            ticketModels.Add(ticketModel);

            var result = await _tenantRepository.AddTickets(ticketModels, _tenantId);

            Assert.IsNotNull(result);
            Assert.IsTrue(result);
        }

        [TestMethod]
        public void GetTicketsSoldTest()
        {
            var result = (_tenantRepository.GetTicketsSold(1, 1, _tenantId)).Result;

            Assert.AreEqual(_ticketsSold, result);
        }

        [TestMethod]
        public async Task GetVenueDetailsTest()
        {
            var result = await _tenantRepository.GetVenueDetails(_tenantId);

            Assert.IsNotNull(result);
            Assert.AreEqual("USA", result.CountryCode);
            Assert.AreEqual("pop", result.VenueType);
            Assert.AreEqual("Venue 1", result.VenueName);
            Assert.AreEqual("123", result.PostalCode);
            Assert.AreEqual("admin@email.com", result.AdminEmail);
            Assert.AreEqual("password", result.AdminPassword);
        }

        [TestMethod]
        public async Task GetVenueTypeTest()
        {
            var result = await _tenantRepository.GetVenueType("pop", _tenantId);

            Assert.IsNotNull(result);
            Assert.AreEqual("en-us", result.Language);
            Assert.AreEqual("pop", result.VenueType);
            Assert.AreEqual("event short name", result.EventTypeShortNamePlural);
            Assert.AreEqual("classic", result.EventTypeName);
            Assert.AreEqual("type 1", result.VenueTypeName);
            Assert.AreEqual("short name", result.EventTypeShortName);
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
