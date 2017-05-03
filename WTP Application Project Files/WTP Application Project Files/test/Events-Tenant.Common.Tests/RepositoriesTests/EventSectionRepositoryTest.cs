using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Tests.MockRepositories;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Events_Tenant.Common.Tests.RepositoriesTests
{
    [TestClass]
    public class EventSectionRepositoryTest
    {
        private IEventSectionRepository _eventSectionRepository;
        private string _connectionString;
        private int _tenantId;

        [TestMethod]
        public void GetEventSectionsTest()
        {
            _eventSectionRepository = new MockEventSectionRepository();
            _connectionString = "User ID=developer;Password=password;Connect Timeout=0;Application Name=EntityFramework";
            _tenantId = 1368421345;

            var result = _eventSectionRepository.GetEventSections(1, _connectionString, _tenantId);

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

    }
}
