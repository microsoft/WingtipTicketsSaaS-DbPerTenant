using System.Collections.Generic;
using Events_Tenant.Common.Models;

namespace Events_TenantUserApp.ViewModels
{
    public class FindSeatViewModel
    {
        public EventModel EventDetails { get; set; }
        public int SectionId { get; set; }
        public List<SectionModel> SeatSections { get; set; }
        public int SeatsAvailable { get; set; }
    }
}
