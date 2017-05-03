using System;
using System.Collections.Generic;

namespace Events_TenantUserApp.EF.CatalogDB
{
    public partial class ShardsGlobal
    {
        public ShardsGlobal()
        {
            ShardMappingsGlobal = new HashSet<ShardMappingsGlobal>();
        }

        public Guid ShardId { get; set; }
        public bool Readable { get; set; }
        public Guid Version { get; set; }
        public Guid ShardMapId { get; set; }
        public Guid? OperationId { get; set; }
        public int Protocol { get; set; }
        public string ServerName { get; set; }
        public int Port { get; set; }
        public string DatabaseName { get; set; }
        public int Status { get; set; }

        public virtual ICollection<ShardMappingsGlobal> ShardMappingsGlobal { get; set; }
        public virtual ShardMapsGlobal ShardMap { get; set; }
    }
}
