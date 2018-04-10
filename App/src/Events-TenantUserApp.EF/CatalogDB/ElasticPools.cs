using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Events_TenantUserApp.EF.CatalogDB
{
    public partial class ElasticPools
    {
        public string ServerName { get; set; }
        public string ElasticPoolName { get; set; }        
        public string Edition { get; set; }
        public int Dtu { get; set; }
        public int DatabaseDtuMax { get; set; }
        public int DatabaseDtuMin { get; set; }
        public int StorageMB { get; set; }
        public string State { get; set; }
        public string RecoveryState { get; set; }
        public System.DateTime LastUpdated { get; set; }
    }
}
