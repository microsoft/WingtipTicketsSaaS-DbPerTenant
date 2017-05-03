using System;
using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;
using Events_TenantUserApp.EF.TenantsDB;

namespace Events_Tenant.Common.Core.Repositories
{
    public class TicketPurchaseRepository : BaseRepository, ITicketPurchaseRepository
    {
        public int Add(TicketPurchaseModel ticketPurchaseModel, string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                //password not required to save demo friction
                var ticketPurchase = new TicketPurchases
                {
                    CustomerId = ticketPurchaseModel.CustomerId,
                    PurchaseDate = DateTime.Now,
                    PurchaseTotal = ticketPurchaseModel.PurchaseTotal
                };

                context.TicketPurchases.Add(ticketPurchase);
                context.SaveChanges();

                return ticketPurchase.TicketPurchaseId;
            }
        }

        public int GetNumberOfTicketPurchases(string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                var ticketPurchases = context.TicketPurchases;
                if (ticketPurchases.Any())
                {
                    return ticketPurchases.Count();
                }
            }
            return 0;
        }
    }
}
