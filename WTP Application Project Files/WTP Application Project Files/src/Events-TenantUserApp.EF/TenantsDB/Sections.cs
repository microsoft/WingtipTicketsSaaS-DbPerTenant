using System.Collections.Generic;

namespace Events_TenantUserApp.EF.TenantsDB
{
    public partial class Sections
    {
        public Sections()
        {
            EventSections = new HashSet<EventSections>();
        }

        public int SectionId { get; set; }
        public string SectionName { get; set; }
        public short SeatRows { get; set; }
        public short SeatsPerRow { get; set; }
        public decimal StandardPrice { get; set; }

        public virtual ICollection<EventSections> EventSections { get; set; }
    }
}
