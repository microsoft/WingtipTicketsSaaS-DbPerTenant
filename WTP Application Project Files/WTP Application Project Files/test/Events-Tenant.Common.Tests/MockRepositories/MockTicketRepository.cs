using System.Collections.Generic;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Tests.MockRepositories
{
    public class MockTicketRepository : ITicketRepository
    {
        public List<TicketModel> TicketModels { get; set; }

        public MockTicketRepository()
        {
            TicketModels = new List<TicketModel>
            {
                new TicketModel
                {
                    SectionId = 1,
                    EventId = 1,
                    TicketPurchaseId = 12,
                    SeatNumber = 50,
                    RowNumber = 2,
                    TicketId = 2
                }
            };
        }

        public bool Add(TicketModel ticketModel, string connectionString, int tenantId)
        {
            TicketModels.Add(ticketModel);
            return true;
        }

        public int GetTicketsSold(int sectionId, int eventId, string connectionString, int tenantId)
        {
            return TicketModels.Count;
        }
    }
}
