using System;
using System.Collections.Generic;

namespace Events_TenantUserApp.EF.TenantsDB
{
    public partial class TicketPurchases
    {
        public TicketPurchases()
        {
            Tickets = new HashSet<Tickets>();
        }

        public int TicketPurchaseId { get; set; }
        public DateTime PurchaseDate { get; set; }
        public decimal PurchaseTotal { get; set; }
        public int CustomerId { get; set; }

        public virtual ICollection<Tickets> Tickets { get; set; }
        public virtual Customers Customer { get; set; }
    }
}
