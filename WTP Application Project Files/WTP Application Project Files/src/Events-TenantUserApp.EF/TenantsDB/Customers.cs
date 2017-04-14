using System.Collections.Generic;

namespace Events_TenantUserApp.EF.TenantsDB
{
    public partial class Customers
    {
        public Customers()
        {
            TicketPurchases = new HashSet<TicketPurchases>();
        }

        public int CustomerId { get; set; }
        public string FirstName { get; set; }
        public string LastName { get; set; }
        public string Email { get; set; }
        public string Password { get; set; }
        public string PostalCode { get; set; }
        public string CountryCode { get; set; }

        public virtual ICollection<TicketPurchases> TicketPurchases { get; set; }
        public virtual Countries CountryCodeNavigation { get; set; }
    }
}
