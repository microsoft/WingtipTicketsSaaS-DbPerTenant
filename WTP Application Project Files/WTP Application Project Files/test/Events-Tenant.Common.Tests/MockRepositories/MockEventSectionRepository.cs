using System.Collections.Generic;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Tests.MockRepositories
{
    public class MockEventSectionRepository : IEventSectionRepository
    {
        public List<EventSectionModel>  EventSectionModels { get; set; }

        public MockEventSectionRepository()
        {
            EventSectionModels = new List<EventSectionModel>
            {
                new EventSectionModel
                {
                    SectionId = 1,
                    EventId = 1,
                    Price = 100
                },
                new EventSectionModel
                {
                    SectionId = 2,
                    EventId = 1,
                    Price = 80
                },
                new EventSectionModel
                {
                    SectionId = 3,
                    EventId = 1,
                    Price = 60
                }
            };

        }

        public List<EventSectionModel> GetEventSections(int eventId, string connectionString, int tenantId)
        {
            return EventSectionModels;
        }
    }
}
