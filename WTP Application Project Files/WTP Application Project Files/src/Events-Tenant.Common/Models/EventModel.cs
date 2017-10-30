using System;

namespace Events_Tenant.Common.Models
{
    public class EventModel
    {
        public int EventId { get; set; }
        public DateTime Date { get; set; }
        public string EventName { get; set; }
        public string SubTitle { get; set; }
    }
}
