using System;

namespace Events_Tenant.Common.Models
{
    public class TicketPurchaseModel
    {
        public int TicketPurchaseId { get; set; }
        public DateTime PurchaseDate { get; set; }
        public decimal PurchaseTotal { get; set; }
        public int CustomerId { get; set; }
    }
}
