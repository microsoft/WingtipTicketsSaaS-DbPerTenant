using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Core.Interfaces
{
    public interface IVenuesRepository
    {
        VenueModel GetVenueDetails(string connectionString, int tenantId);
    }
}
