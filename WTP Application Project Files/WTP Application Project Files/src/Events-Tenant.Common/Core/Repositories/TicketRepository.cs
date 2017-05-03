using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;
using Events_TenantUserApp.EF.TenantsDB;

namespace Events_Tenant.Common.Core.Repositories
{
    public class TicketRepository : BaseRepository, ITicketRepository
    {
        public bool Add(TicketModel ticketModel, string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                var ticket = new Tickets
                {
                    TicketPurchaseId = ticketModel.TicketPurchaseId,
                    SectionId = ticketModel.SectionId,
                    EventId = ticketModel.EventId,
                    RowNumber = ticketModel.RowNumber,
                    SeatNumber = ticketModel.SeatNumber
                };

                context.Tickets.Add(ticket);
                context.SaveChanges();
            }
            return true;
        }

        public int GetTicketsSold(int sectionId, int eventId, string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                var tickets = context.Tickets.Where(i => i.SectionId == sectionId && i.EventId == eventId);
                if (tickets.Any())
                {
                    return tickets.Count();
                }
            }
            return 0;
        }

    }
}
