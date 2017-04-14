using System.Collections.Generic;

namespace Events_TenantUserApp.EF.TenantsDB
{
    public partial class EventSections
    {
        public EventSections()
        {
            Tickets = new HashSet<Tickets>();
        }

        public int EventId { get; set; }
        public int SectionId { get; set; }
        public decimal Price { get; set; }

        public virtual ICollection<Tickets> Tickets { get; set; }
        public virtual Events Event { get; set; }
        public virtual Sections Section { get; set; }
    }
}
