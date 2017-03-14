namespace Events_Tenant.Common.Models
{
    public class TenantModel
    {
        public byte[] TenantId { get; set; }
        public string TenantName { get; set; }
        public string ServicePlan { get; set; }
        public string VenueName { get; set; }
    }
}
