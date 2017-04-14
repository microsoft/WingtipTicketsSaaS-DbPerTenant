using System;
using System.Collections.Generic;

namespace Events_TenantUserApp.EF.CatalogDB
{
    public partial class ShardMapsGlobal
    {
        public ShardMapsGlobal()
        {
            ShardMappingsGlobal = new HashSet<ShardMappingsGlobal>();
            ShardsGlobal = new HashSet<ShardsGlobal>();
        }

        public Guid ShardMapId { get; set; }
        public string Name { get; set; }
        public int ShardMapType { get; set; }
        public int KeyType { get; set; }

        public virtual ICollection<ShardMappingsGlobal> ShardMappingsGlobal { get; set; }
        public virtual ICollection<ShardsGlobal> ShardsGlobal { get; set; }
    }
}
