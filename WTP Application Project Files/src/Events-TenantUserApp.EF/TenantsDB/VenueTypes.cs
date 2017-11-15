using System.Collections.Generic;

namespace Events_TenantUserApp.EF.TenantsDB
{
    public partial class VenueTypes
    {
        public VenueTypes()
        {
            Venue = new HashSet<Venue>();
        }

        public string VenueType { get; set; }
        public string VenueTypeName { get; set; }
        public string EventTypeName { get; set; }
        public string EventTypeShortName { get; set; }
        public string EventTypeShortNamePlural { get; set; }
        public string Language { get; set; }

        public virtual ICollection<Venue> Venue { get; set; }
    }
}
