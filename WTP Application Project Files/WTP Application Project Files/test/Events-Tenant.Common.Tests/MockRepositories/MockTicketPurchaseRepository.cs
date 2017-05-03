using System;
using System.Collections.Generic;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Tests.MockRepositories
{
    public class MockTicketPurchaseRepository : ITicketPurchaseRepository
    {
        public List<TicketPurchaseModel> TicketPurchaseModels { get; set; }

        public MockTicketPurchaseRepository()
        {
            TicketPurchaseModels = new List<TicketPurchaseModel>
            {
                new TicketPurchaseModel
                {
                    CustomerId = 1,
                    PurchaseTotal = 2,
                    TicketPurchaseId = 5,
                    PurchaseDate = DateTime.Now
                }
            };
        }

        public int Add(TicketPurchaseModel ticketPurchaseModel, string connectionString, int tenantId)
        {
            TicketPurchaseModels.Add(ticketPurchaseModel);
            return ticketPurchaseModel.TicketPurchaseId;
        }

        public int GetNumberOfTicketPurchases(string connectionString, int tenantId)
        {
            return TicketPurchaseModels.Count;
        }
    }
}