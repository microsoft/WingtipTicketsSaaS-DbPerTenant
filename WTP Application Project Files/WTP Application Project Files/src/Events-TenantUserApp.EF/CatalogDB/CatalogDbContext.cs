using Microsoft.EntityFrameworkCore;

namespace Events_TenantUserApp.EF.CatalogDB
{
    public partial class CatalogDbContext : DbContext
    {
        public virtual DbSet<Tenants> Tenants { get; set; }

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
            });
        }
    }
}