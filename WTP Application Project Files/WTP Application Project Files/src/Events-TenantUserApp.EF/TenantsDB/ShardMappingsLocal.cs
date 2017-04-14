using System;

namespace Events_TenantUserApp.EF.TenantsDB
{
    public partial class ShardMappingsLocal
    {
        public Guid MappingId { get; set; }
        public Guid ShardId { get; set; }
        public Guid ShardMapId { get; set; }
        public byte[] MinValue { get; set; }
        public byte[] MaxValue { get; set; }
        public int Status { get; set; }
        public Guid LockOwnerId { get; set; }
        public Guid LastOperationId { get; set; }

        public virtual ShardsLocal Shard { get; set; }
        public virtual ShardMapsLocal ShardMap { get; set; }
    }
}
