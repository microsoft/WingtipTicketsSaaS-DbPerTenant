using Events_Tenant.Common.Tests.MockRepositories;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Events_Tenant.Common.Tests.RepositoriesTests
{
    [TestClass]
    public class VenuesRepositoryTests
    {
    
        [TestMethod]
        public void GetVenueDetailsTest()
        {
            var venuesRepository = new MockVenuesRepository();
            string connectionString = "User ID=developer;Password=password;Connect Timeout=0;Application Name=EntityFramework";
            int tenantId = 1368421345;

            var result = venuesRepository.GetVenueDetails(connectionString, tenantId);

            Assert.IsNotNull(result);
            Assert.AreEqual("USA", result.CountryCode);
            Assert.AreEqual("pop", result.VenueType);
            Assert.AreEqual("Venue 1", result.VenueName);
            Assert.AreEqual("123", result.PostalCode);
            Assert.AreEqual("admin@email.com", result.AdminEmail);
            Assert.AreEqual("password", result.AdminPassword);
        }
    }
}
