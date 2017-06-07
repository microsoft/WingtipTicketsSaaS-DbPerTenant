using System.Collections.Generic;
using Events_Tenant.Common.Models;
using Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement;

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
        //public string SqlProtocol { get; set; }
        public int ConnectionTimeOut { get; set; }
        public string LearnHowFooterUrl { get; set; }
        public SqlProtocol SqlProtocol { get; set; }
    }

    /// <summary>
    /// The catalog settings
    /// </summary>
    public class CatalogConfig
    {
        public string CatalogServer { get; set; }
        public string CatalogDatabase { get; set; }
        public string ServicePlan { get; set; }
    }

    /// <summary>
    /// The Tenant server configs
    /// </summary>
    public class TenantServerConfig
    {
        public string TenantServer { get; set; }

        /// <summary>
        /// Boolean value to specify if the events dates need to be reset
        /// This can be set to false when in Development mode
        /// </summary>
        /// <value>
        ///   <c>true</c> if [reset event dates]; otherwise, <c>false</c>.
        /// </value>
        public bool ResetEventDates { get; set; }
    }

    /// <summary>
    /// The tenant configs
    /// </summary>
    public class TenantConfig
    {
        public int TenantId { get; set; }
        public string VenueName { get; set; }
        public string EventTypeNamePlural { get; set; }
        public string BlobImagePath { get; set; }
        public string BlobPath { get; set; }
        public string TenantName { get; set; }
        public string Currency { get; set; }
        public string TenantCulture { get; set; }
        public List<CountryModel> TenantCountries { get; set; }
        public string TenantIdInString { get; set; }
        public string User { get; set; }
    }

}
