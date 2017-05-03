using System;
using System.Collections.Generic;
using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Core.Repositories
{
    public class EventsRepository : BaseRepository, IEventsRepository
    {
        public List<EventModel> GetEventsForTenant(string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                //Past events (yesterday and earlier) are not shown 
                var events = context.Events.Where(i => i.Date >= DateTime.Now).OrderBy(x => x.Date);

                return events.Select(eventmodel => new EventModel
                {
                    Date = eventmodel.Date,
                    EventId = eventmodel.EventId,
                    EventName = eventmodel.EventName.Trim(),
                    SubTitle = eventmodel.Subtitle.Trim()
                }).ToList();
            }
        }

        public EventModel GetEvent(int eventId, string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                var events = context.Events.Where(i => i.EventId == eventId);

                if (events.Any())
                {
                    var eventModel = events.FirstOrDefault();

                    return new EventModel
                    {
                        Date = eventModel.Date,
                        EventName = eventModel.EventName,
                        EventId = eventModel.EventId,
                        SubTitle = eventModel.Subtitle
                    };
                }
            }
            return null;
        }
    }
}
