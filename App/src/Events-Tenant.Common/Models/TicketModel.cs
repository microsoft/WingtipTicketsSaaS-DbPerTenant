namespace Events_Tenant.Common.Models
{
    public class TicketModel
    {
        public int TicketId { get; set; }
        public int RowNumber { get; set; }
        public int SeatNumber { get; set; }
        public int EventId { get; set; }
        public int SectionId { get; set; }
        public int TicketPurchaseId { get; set; }
    }
}


