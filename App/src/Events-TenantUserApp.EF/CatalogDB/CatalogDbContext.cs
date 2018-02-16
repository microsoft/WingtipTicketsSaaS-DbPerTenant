using Microsoft.EntityFrameworkCore;

namespace Events_TenantUserApp.EF.CatalogDB
{
    public partial class CatalogDbContext : DbContext
    {
        public virtual DbSet<Tenants> Tenants { get; set; }
        public virtual DbSet<Databases> Databases { get; set; }
        public virtual DbSet<ElasticPools> ElasticPools { get; set; }
        public virtual DbSet<Servers> Servers { get; set; }

        public CatalogDbContext(DbContextOptions<CatalogDbContext> options) :
          base(options)
        {

        }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Tenants>(entity =>
            {
                entity.HasKey(e => e.TenantId)
                    .HasName("PK__Tenants__2E9B47E15565CFCB");

                entity.HasIndex(e => e.TenantName)
                    .HasName("IX_Tenants_TenantName");

                entity.Property(e => e.TenantId).HasMaxLength(128);

                entity.Property(e => e.ServicePlan)
                    .IsRequired()
                    .HasMaxLength(30)
                    .HasDefaultValueSql("'standard'");

                entity.Property(e => e.TenantName)
                    .IsRequired()
                    .HasMaxLength(50);

                entity.Property(e => e.TenantAlias)
                    .IsRequired()
                    .HasMaxLength(65);

                entity.Property(e => e.RecoveryState)
                    .IsRequired()
                    .HasMaxLength(30);

                entity.Property(e => e.LastUpdated)
                    .IsRequired();
            });

            modelBuilder.Entity<Databases>(entity =>
            {
                entity.HasKey(e => new { e.ServerName, e.DatabaseName });

                entity.Property(e => e.ServerName)
                    .IsRequired()
                    .HasMaxLength(128);

                entity.Property(e => e.DatabaseName)
                    .IsRequired()
                    .HasMaxLength(128);

                entity.Property(e => e.ServiceObjective)
                    .IsRequired()
                    .HasMaxLength(50);

                entity.Property(e => e.ElasticPoolName)
                    .IsRequired()
                    .HasMaxLength(128);

                entity.Property(e => e.State)
                    .IsRequired()
                    .HasMaxLength(30);

                entity.Property(e => e.RecoveryState)
                    .IsRequired()
                    .HasMaxLength(30);

                entity.Property(e => e.LastUpdated)
                    .IsRequired();
            });

            modelBuilder.Entity<ElasticPools>(entity =>
            {
                entity.HasKey(e => new { e.ServerName, e.ElasticPoolName });
                entity.Property(e => e.Dtu)
                    .IsRequired();
                entity.Property(e => e.Edition)
                    .IsRequired()
                    .HasMaxLength(20);
                entity.Property(e => e.DatabaseDtuMax)
                    .IsRequired();
                entity.Property(e => e.DatabaseDtuMin)
                    .IsRequired();
                entity.Property(e => e.StorageMB)
                    .IsRequired();
                entity.Property(e => e.State)
                    .IsRequired()
                    .HasMaxLength(30);
                entity.Property(e => e.RecoveryState)
                    .IsRequired()
                    .HasMaxLength(30);
                entity.Property(e => e.LastUpdated)
                    .IsRequired();
            });

            modelBuilder.Entity<Servers>(entity =>
            {
                entity.HasKey(e => e.ServerName);
                entity.Property(e => e.Location)
                    .IsRequired()
                    .HasMaxLength(30);
                entity.Property(e => e.State)
                    .IsRequired()
                    .HasMaxLength(30);
                entity.Property(e => e.RecoveryState)
                    .IsRequired()
                    .HasMaxLength(30);
                entity.Property(e => e.LastUpdated)
                    .IsRequired();
            });
        }
    }
}