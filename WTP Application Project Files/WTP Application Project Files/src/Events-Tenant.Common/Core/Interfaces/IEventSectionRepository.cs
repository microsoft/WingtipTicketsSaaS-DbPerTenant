using System.Collections.Generic;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Core.Interfaces
{
   public interface IEventSectionRepository
   {
       List<EventSectionModel> GetEventSections(int eventId, string connectionString, int tenantId);
   }
}
