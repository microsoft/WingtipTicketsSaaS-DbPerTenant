using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Tests.MockRepositories
{
    public class MockVenueTypesRepository : IVenueTypesRepository
    {
        public VenueTypeModel GetVenueType(string venueType, string connectionString, int tenantId)
        {
            return new VenueTypeModel
            {
                Language = "en-us",
                VenueType = "pop",
                EventTypeShortNamePlural = "event short name",
                EventTypeName = "classic",
                VenueTypeName = "type 1",
                EventTypeShortName = "short name"
            };
        }
    }
}
