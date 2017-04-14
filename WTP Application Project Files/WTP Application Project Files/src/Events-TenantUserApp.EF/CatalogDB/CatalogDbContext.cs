using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;

namespace Events_TenantUserApp.EF.CatalogDB
{
    public partial class CatalogDbContext : DbContext
    {
        public virtual DbSet<OperationsLogGlobal> OperationsLogGlobal { get; set; }
        public virtual DbSet<ShardMapManagerGlobal> ShardMapManagerGlobal { get; set; }
        public virtual DbSet<ShardMappingsGlobal> ShardMappingsGlobal { get; set; }
        public virtual DbSet<ShardMapsGlobal> ShardMapsGlobal { get; set; }
        public virtual DbSet<ShardedDatabaseSchemaInfosGlobal> ShardedDatabaseSchemaInfosGlobal { get; set; }
        public virtual DbSet<ShardsGlobal> ShardsGlobal { get; set; }
        public virtual DbSet<Tenants> Tenants { get; set; }

        public CatalogDbContext(DbContextOptions<CatalogDbContext> options) :
            base(options)
        {
            
        }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<OperationsLogGlobal>(entity =>
            {
                entity.HasKey(e => e.OperationId)
                    .HasName("pkOperationsLogGlobal_OperationId");

                entity.ToTable("OperationsLogGlobal", "__ShardManagement");

                entity.Property(e => e.OperationId).ValueGeneratedNever();

                entity.Property(e => e.Data)
                    .IsRequired()
                    .HasColumnType("xml");

                entity.Property(e => e.UndoStartState).HasDefaultValueSql("100");
            });

            modelBuilder.Entity<ShardMapManagerGlobal>(entity =>
            {
                entity.HasKey(e => e.StoreVersionMajor)
                    .HasName("pkShardMapManagerGlobal_StoreVersionMajor");

                entity.ToTable("ShardMapManagerGlobal", "__ShardManagement");

                entity.Property(e => e.StoreVersionMajor).ValueGeneratedNever();
            });

            modelBuilder.Entity<ShardMappingsGlobal>(entity =>
            {
                entity.HasKey(e => new { e.ShardMapId, e.MinValue, e.Readable })
                    .HasName("pkShardMappingsGlobal_ShardMapId_MinValue_Readable");

                entity.ToTable("ShardMappingsGlobal", "__ShardManagement");

                entity.HasIndex(e => e.MappingId)
                    .HasName("ucShardMappingsGlobal_MappingId")
                    .IsUnique();

                entity.Property(e => e.MinValue).HasMaxLength(128);

                entity.Property(e => e.LockOwnerId).HasDefaultValueSql("'00000000-0000-0000-0000-000000000000'");

                entity.Property(e => e.MaxValue).HasMaxLength(128);

                entity.HasOne(d => d.Shard)
                    .WithMany(p => p.ShardMappingsGlobal)
                    .HasForeignKey(d => d.ShardId)
                    .OnDelete(DeleteBehavior.Restrict)
                    .HasConstraintName("fkShardMappingsGlobal_ShardId");

                entity.HasOne(d => d.ShardMap)
                    .WithMany(p => p.ShardMappingsGlobal)
                    .HasForeignKey(d => d.ShardMapId)
                    .OnDelete(DeleteBehavior.Restrict)
                    .HasConstraintName("fkShardMappingsGlobal_ShardMapId");
            });

            modelBuilder.Entity<ShardMapsGlobal>(entity =>
            {
                entity.HasKey(e => e.ShardMapId)
                    .HasName("pkShardMapsGlobal_ShardMapId");

                entity.ToTable("ShardMapsGlobal", "__ShardManagement");

                entity.HasIndex(e => e.Name)
                    .HasName("ucShardMapsGlobal_Name")
                    .IsUnique();

                entity.Property(e => e.ShardMapId).ValueGeneratedNever();

                entity.Property(e => e.Name)
                    .IsRequired()
                    .HasMaxLength(50);
            });

            modelBuilder.Entity<ShardedDatabaseSchemaInfosGlobal>(entity =>
            {
                entity.HasKey(e => e.Name)
                    .HasName("pkShardedDatabaseSchemaInfosGlobal_Name");

                entity.ToTable("ShardedDatabaseSchemaInfosGlobal", "__ShardManagement");

                entity.Property(e => e.Name).HasMaxLength(128);

                entity.Property(e => e.SchemaInfo)
                    .IsRequired()
                    .HasColumnType("xml");
            });

            modelBuilder.Entity<ShardsGlobal>(entity =>
            {
                entity.HasKey(e => e.ShardId)
                    .HasName("pkShardsGlobal_ShardId");

                entity.ToTable("ShardsGlobal", "__ShardManagement");

                entity.HasIndex(e => new { e.ShardMapId, e.Protocol, e.ServerName, e.DatabaseName, e.Port })
                    .HasName("ucShardsGlobal_Location")
                    .IsUnique();

                entity.Property(e => e.ShardId).ValueGeneratedNever();

                entity.Property(e => e.DatabaseName)
                    .IsRequired()
                    .HasMaxLength(128);

                entity.Property(e => e.ServerName)
                    .IsRequired()
                    .HasMaxLength(128);

                entity.HasOne(d => d.ShardMap)
                    .WithMany(p => p.ShardsGlobal)
                    .HasForeignKey(d => d.ShardMapId)
                    .OnDelete(DeleteBehavior.Restrict)
                    .HasConstraintName("fkShardsGlobal_ShardMapId");
            });

            modelBuilder.Entity<Tenants>(entity =>
            {
                entity.HasKey(e => e.TenantId)
                    .HasName("PK__Tenants__2E9B47E14F398EA5");

                entity.HasIndex(e => e.TenantName)
                    .HasName("IX_Tenants_TenantName");

                entity.Property(e => e.TenantId).HasMaxLength(128);

                entity.Property(e => e.ServicePlan)
                    .IsRequired()
                    .HasColumnType("char(10)")
                    .HasDefaultValueSql("'standard'");

                entity.Property(e => e.TenantName)
                    .IsRequired()
                    .HasMaxLength(50);
            });
        }
    }
}