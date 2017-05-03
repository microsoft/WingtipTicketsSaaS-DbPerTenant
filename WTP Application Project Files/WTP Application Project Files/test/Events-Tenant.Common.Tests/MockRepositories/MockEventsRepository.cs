using System;
using System.Collections.Generic;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Tests.MockRepositories
{
    public class MockEventsRepository : IEventsRepository
    {
        public List<EventModel> EventModels { get; set; }

        public MockEventsRepository()
        {
            EventModels = new List<EventModel>
            {
                new EventModel
                {
                    EventId = 1,
                    EventName = "Event 1",
                    Date = DateTime.Now,
                    SubTitle = "Event 1 Subtitle"
                },
                new EventModel
                {
                    EventId = 2,
                    EventName = "Event 2",
                    Date = DateTime.Now,
                    SubTitle = "Event 2 Subtitle"
                }
            };
        }

        public List<EventModel> GetEventsForTenant(string connectionString, int tenantId)
        {
            return EventModels;
        }

        public EventModel GetEvent(int eventId, string connectionString, int tenantId)
        {
            return EventModels[0];
        }
    }
}
