using System;

namespace Events_TenantUserApp.EF.CatalogDB
{
    public partial class ShardMappingsGlobal
    {
        public Guid MappingId { get; set; }
        public bool Readable { get; set; }
        public Guid ShardId { get; set; }
        public Guid ShardMapId { get; set; }
        public Guid? OperationId { get; set; }
        public byte[] MinValue { get; set; }
        public byte[] MaxValue { get; set; }
        public int Status { get; set; }
        public Guid LockOwnerId { get; set; }

        public virtual ShardsGlobal Shard { get; set; }
        public virtual ShardMapsGlobal ShardMap { get; set; }
    }
}
