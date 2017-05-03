using Events_Tenant.Common.Tests.MockRepositories;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Events_Tenant.Common.Tests.RepositoriesTests
{
    [TestClass]
    public class VenueTypesRepositoryTests
    {
        [TestMethod]
        public void GetVenueTypeTest()
        {
            var venueTypesRepository = new MockVenueTypesRepository();
            string connectionString = "User ID=developer;Password=password;Connect Timeout=0;Application Name=EntityFramework";
            int tenantId = 1368421345;

            var result = venueTypesRepository.GetVenueType("pop", connectionString, tenantId);

            Assert.IsNotNull(result);
            Assert.AreEqual("en-us", result.Language);
            Assert.AreEqual("pop", result.VenueType);
            Assert.AreEqual("event short name", result.EventTypeShortNamePlural);
            Assert.AreEqual("classic", result.EventTypeName);
            Assert.AreEqual("type 1", result.VenueTypeName);
            Assert.AreEqual("short name", result.EventTypeShortName);
        }
    }
}
