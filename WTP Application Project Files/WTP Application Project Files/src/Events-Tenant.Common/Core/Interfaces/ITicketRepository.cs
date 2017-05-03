using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Core.Interfaces
{
    public interface ITicketRepository
    {
        bool Add(TicketModel ticketModel, string connectionString, int tenantId);

        int GetTicketsSold(int sectionId, int eventId, string connectionString, int tenantId);
    }
}
