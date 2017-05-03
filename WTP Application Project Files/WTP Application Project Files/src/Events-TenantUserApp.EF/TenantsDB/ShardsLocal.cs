using System;
using System.Collections.Generic;

namespace Events_TenantUserApp.EF.TenantsDB
{
    public partial class ShardsLocal
    {
        public ShardsLocal()
        {
            ShardMappingsLocal = new HashSet<ShardMappingsLocal>();
        }

        public Guid ShardId { get; set; }
        public Guid Version { get; set; }
        public Guid ShardMapId { get; set; }
        public int Protocol { get; set; }
        public string ServerName { get; set; }
        public int Port { get; set; }
        public string DatabaseName { get; set; }
        public int Status { get; set; }
        public Guid LastOperationId { get; set; }

        public virtual ICollection<ShardMappingsLocal> ShardMappingsLocal { get; set; }
        public virtual ShardMapsLocal ShardMap { get; set; }
    }
}
