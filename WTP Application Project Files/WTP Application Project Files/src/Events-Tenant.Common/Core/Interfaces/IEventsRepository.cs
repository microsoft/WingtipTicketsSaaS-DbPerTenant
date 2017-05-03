using System.Collections.Generic;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Core.Interfaces
{
    public interface IEventsRepository
    {
        List<EventModel> GetEventsForTenant(string connectionString, int tenantId);
        EventModel GetEvent(int eventId, string connectionString, int tenantId);
    }
}
