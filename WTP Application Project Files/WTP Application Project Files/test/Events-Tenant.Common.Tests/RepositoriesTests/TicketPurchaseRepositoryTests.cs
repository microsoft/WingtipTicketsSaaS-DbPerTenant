using System;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Tests.MockRepositories;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Events_Tenant.Common.Tests.RepositoriesTests
{
    [TestClass]
    public class TicketPurchaseRepositoryTests
    {
        private ITicketPurchaseRepository _ticketPurchaseRepository;
        private string _connectionString;
        private int _tenantId;
        private int _numberOfTicketPurchases;

        [TestInitialize]
        public void Setup()
        {
            _ticketPurchaseRepository = new MockTicketPurchaseRepository();
            _connectionString = "User ID=developer;Password=password;Connect Timeout=0;Application Name=EntityFramework";
            _tenantId = 1368421345;
            _numberOfTicketPurchases = 1;
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

            var result = _ticketPurchaseRepository.Add(ticketPurchaseModel, _connectionString, _tenantId);
            _numberOfTicketPurchases++;

            Assert.IsNotNull(result);
            Assert.AreEqual(_numberOfTicketPurchases, 2);
            Assert.AreEqual(12, result);

        }

        [TestMethod]
        public void GetNumberOfTicketPurchasesTest()
        {
            var result = _ticketPurchaseRepository.GetNumberOfTicketPurchases(_connectionString, _tenantId);

            Assert.AreEqual(_numberOfTicketPurchases, result);
        }
    }
}
