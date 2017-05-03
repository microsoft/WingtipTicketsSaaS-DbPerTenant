using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Tests.MockRepositories;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Events_Tenant.Common.Tests.RepositoriesTests
{
    [TestClass]
    public class TicketRepositoryTests
    {
        private ITicketRepository _ticketRepository;
        private string _connectionString;
        private int _tenantId;
        private int _ticketsSold;

        [TestInitialize]
        public void Setup()
        {
            _ticketRepository = new MockTicketRepository();
            _connectionString = "User ID=developer;Password=password;Connect Timeout=0;Application Name=EntityFramework";
            _tenantId = 1368421345;
            _ticketsSold = 1;
        }


        [TestMethod]
        public void AddTicketTest()
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

            var result = _ticketRepository.Add(ticketModel, _connectionString, _tenantId);
            _ticketsSold++;

            Assert.IsNotNull(result);
            Assert.IsTrue(result);
        }

        [TestMethod]
        public void GetTicketsSoldTest()
        {
            var result = _ticketRepository.GetTicketsSold(1, 1, _connectionString, _tenantId);

            Assert.AreEqual(_ticketsSold, result);
        }
    }
}
