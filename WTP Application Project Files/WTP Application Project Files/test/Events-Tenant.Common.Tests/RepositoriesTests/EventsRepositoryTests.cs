using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Tests.MockRepositories;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Events_Tenant.Common.Tests.RepositoriesTests
{
    [TestClass]
    public class EventsRepositoryTests
    {
        private IEventsRepository _eventsRepository;
        private string _connectionString;
        private int _tenantId;

        [TestInitialize]
        public void Setup()
        {
            _eventsRepository = new MockEventsRepository();
            _connectionString = "User ID=developer;Password=password;Connect Timeout=0;Application Name=EntityFramework";
            _tenantId = 1368421345;
        }

        [TestMethod]
        public void GetEventsForTenantTest()
        {
            var result = _eventsRepository.GetEventsForTenant(_connectionString, _tenantId);
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
        public void GetEventTest()
        {
            var result = _eventsRepository.GetEvent(1, _connectionString, _tenantId);

            Assert.IsNotNull(result);
            Assert.AreEqual(1, result.EventId);
            Assert.AreEqual("Event 1", result.EventName);
            Assert.AreEqual("Event 1 Subtitle", result.SubTitle);
        }
    }
}
