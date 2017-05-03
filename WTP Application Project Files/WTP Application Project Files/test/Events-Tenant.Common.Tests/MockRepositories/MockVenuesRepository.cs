using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Tests.MockRepositories
{
    public class MockVenuesRepository : IVenuesRepository
    {
        public VenueModel GetVenueDetails(string connectionString, int tenantId)
        {
            return new VenueModel
            {
                CountryCode = "USA",
                VenueType = "pop",
                VenueName = "Venue 1",
                PostalCode = "123",
                AdminEmail = "admin@email.com",
                AdminPassword = "password"
            };
        }
    }
}