using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;

namespace Events_Tenant.Common.Core.Interfaces
{
    public interface IVenuesRepository
    {
        VenueModel GetVenueDetails(byte[] tenantId, DatabaseConfig databaseConfig, TenantServerConfig tenantServerConfig);
    }
}
