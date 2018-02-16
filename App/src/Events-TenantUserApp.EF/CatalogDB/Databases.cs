using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Events_TenantUserApp.EF.CatalogDB
{
    public partial class Databases
    {
        public string ServerName { get; set; }
        public string DatabaseName { get; set; }
        public string ServiceObjective { get; set; }
        public string ElasticPoolName { get; set; }
        public string State { get; set; }
        public string RecoveryState { get; set; }
        public System.DateTime LastUpdated { get; set; }
    }
}
