namespace Events_Tenant.Common.Utilities
{
    /// <summary>
    /// Common database settings
    /// </summary>
    public class DatabaseConfig
    {
        public string DatabaseUser { get; set; }
        public string DatabasePassword { get; set; }
        public int DatabaseServerPort { get; set; }
        public string SqlProtocol { get; set; }
        public int ConnectionTimeOut { get; set; }
    }

    /// <summary>
    /// The customer catalog settings
    /// </summary>
    public class CustomerCatalogConfig
    {
        public string CustomerCatalogServer { get; set; }
        public string CustomerCatalogDatabase { get; set; }
        public string ServicePlan { get; set; }
    }

    /// <summary>
    /// The Tenant server configs
    /// </summary>
    public class TenantServerConfig
    {
        public string TenantServer { get; set; }
        public bool ResetEventDates { get; set; }
    }

    /// <summary>
    /// The tenant configs
    /// </summary>
    public class TenantConfig
    {
        public string TenantId { get; set; }
        public string VenueName { get; set; }
        public string EventTypeImage { get; set; }
        public string EventTypeNamePlural { get; set; }
    }

}
