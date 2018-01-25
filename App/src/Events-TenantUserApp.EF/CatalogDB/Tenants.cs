namespace Events_TenantUserApp.EF.CatalogDB
{
    public partial class Tenants
    {
        public byte[] TenantId { get; set; }
        public string TenantAlias { get; set; }
        public string TenantName { get; set; }
        public string ServicePlan { get; set; }
        public string RecoveryState { get; set; }
        public System.DateTime LastUpdated { get; set; }
    }
}
