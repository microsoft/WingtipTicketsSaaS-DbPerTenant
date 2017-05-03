using System.Collections.Generic;
using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Core.Repositories
{
    public class EventSectionRepository : BaseRepository, IEventSectionRepository
    {
        public List<EventSectionModel> GetEventSections(int eventId, string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                var eventsections = context.EventSections.Where(i => i.EventId == eventId);

                return eventsections.Select(eventSectionModel => new EventSectionModel
                {
                    EventId = eventSectionModel.EventId,
                    Price = eventSectionModel.Price,
                    SectionId = eventSectionModel.SectionId

                }).ToList();
            }
        }
    }
}
