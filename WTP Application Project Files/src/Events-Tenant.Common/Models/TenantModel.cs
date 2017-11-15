namespace Events_Tenant.Common.Models
{
    public class TenantModel
    {
        public int TenantId { get; set; }
        public string TenantName { get; set; }
        public string ServicePlan { get; set; }
        public string VenueName { get; set; }
        public string TenantIdInString { get; set; }
    }
}
