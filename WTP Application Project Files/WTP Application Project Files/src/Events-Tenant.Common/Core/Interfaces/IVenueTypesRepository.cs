using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Core.Interfaces
{
    public interface IVenueTypesRepository
    {
        VenueTypeModel GetVenueType(string venueType, string connectionString, int tenantId);
    }
}
