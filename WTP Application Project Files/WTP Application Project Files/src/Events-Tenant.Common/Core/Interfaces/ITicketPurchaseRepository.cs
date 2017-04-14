using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Core.Interfaces
{
  public  interface ITicketPurchaseRepository
  {
      int Add(TicketPurchaseModel ticketPurchaseModel, string connectionString, int tenantId);

      int GetNumberOfTicketPurchases(string connectionString, int tenantId);
  }
}
