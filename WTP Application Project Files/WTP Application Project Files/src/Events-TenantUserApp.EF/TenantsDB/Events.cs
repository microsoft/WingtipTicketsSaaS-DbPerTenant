using System;
using System.Collections.Generic;

namespace Events_TenantUserApp.EF.TenantsDB
{
    public partial class Events
    {
        public Events()
        {
            EventSections = new HashSet<EventSections>();
        }

        public int EventId { get; set; }
        public string EventName { get; set; }
        public string Subtitle { get; set; }
        public DateTime Date { get; set; }

        public virtual ICollection<EventSections> EventSections { get; set; }
    }
}
