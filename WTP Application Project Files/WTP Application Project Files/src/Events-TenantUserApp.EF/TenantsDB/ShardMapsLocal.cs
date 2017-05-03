using System;
using System.Collections.Generic;

namespace Events_TenantUserApp.EF.TenantsDB
{
    public partial class ShardMapsLocal
    {
        public ShardMapsLocal()
        {
            ShardMappingsLocal = new HashSet<ShardMappingsLocal>();
            ShardsLocal = new HashSet<ShardsLocal>();
        }

        public Guid ShardMapId { get; set; }
        public string Name { get; set; }
        public int MapType { get; set; }
        public int KeyType { get; set; }
        public Guid LastOperationId { get; set; }

        public virtual ICollection<ShardMappingsLocal> ShardMappingsLocal { get; set; }
        public virtual ICollection<ShardsLocal> ShardsLocal { get; set; }
    }
}
