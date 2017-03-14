using System.Collections.Generic;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;

namespace Events_Tenant.Common.Core.Interfaces
{
    public interface IEventsRepository
    {
        IEnumerable<EventModel> GetEventsForTenant(byte[] tenantId, DatabaseConfig databaseConfig, TenantServerConfig tenantServerConfig);
    }
}
