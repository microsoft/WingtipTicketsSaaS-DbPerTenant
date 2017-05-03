using System;
using System.Data.SqlClient;
using Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;

namespace Events_TenantUserApp.EF.TenantsDB
{
    public partial class TenantDbContext : DbContext
    {
        public virtual DbSet<Countries> Countries { get; set; }
        public virtual DbSet<Customers> Customers { get; set; }
        public virtual DbSet<EventSections> EventSections { get; set; }
        public virtual DbSet<Events> Events { get; set; }
        public virtual DbSet<Sections> Sections { get; set; }
        public virtual DbSet<TicketPurchases> TicketPurchases { get; set; }
        public virtual DbSet<Tickets> Tickets { get; set; }
        public virtual DbSet<Venue> Venue { get; set; }
        public virtual DbSet<VenueTypes> VenueTypes { get; set; }

        public TenantDbContext(ShardMap shardMap, int shardingKey, string connectionStr) :
            base(CreateDdrConnection(shardMap, shardingKey, connectionStr))
        {

        }

        /// <summary>
        /// Creates the DDR (Data Dependent Routing) connection.
        /// </summary>
        /// <param name="shardMap">The shard map.</param>
        /// <param name="shardingKey">The sharding key.</param>
        /// <param name="connectionStr">The connection string.</param>
        /// <returns></returns>
        private static DbContextOptions CreateDdrConnection(ShardMap shardMap, int shardingKey, string connectionStr)
        {
            // Ask shard map to broker a validated connection for the given key
            SqlConnection sqlConn = shardMap.OpenConnectionForKey(shardingKey, connectionStr);

            var optionsBuilder = new DbContextOptionsBuilder<TenantDbContext>();
            var options = optionsBuilder.UseSqlServer(sqlConn).Options;

            return options;
        }


        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Countries>(entity =>
            {
                entity.HasKey(e => e.CountryCode)
                    .HasName("PK__Countrie__5D9B0D2D5E8496A7");

                entity.HasIndex(e => new { e.CountryCode, e.Language })
                    .HasName("IX_Countries_Country_Language")
                    .IsUnique();

                entity.Property(e => e.CountryCode).HasColumnType("char(3)");

                entity.Property(e => e.CountryName)
                    .IsRequired()
                    .HasMaxLength(50);

                entity.Property(e => e.Language)
                    .IsRequired()
                    .HasColumnType("char(8)")
                    .HasDefaultValueSql("'en'");
            });

            modelBuilder.Entity<Customers>(entity =>
            {
                entity.HasKey(e => e.CustomerId)
                    .HasName("PK__Customer__A4AE64D814038057");

                entity.HasIndex(e => e.Email)
                    .HasName("IX_Customers_Email")
                    .IsUnique();

                entity.Property(e => e.CountryCode)
                    .IsRequired()
                    .HasColumnType("char(3)");

                entity.Property(e => e.Email)
                    .IsRequired()
                    .HasColumnType("varchar(50)");

                entity.Property(e => e.FirstName)
                    .IsRequired()
                    .HasMaxLength(25);

                entity.Property(e => e.LastName)
                    .IsRequired()
                    .HasMaxLength(25);

                entity.Property(e => e.Password).HasMaxLength(30);

                entity.Property(e => e.PostalCode).HasColumnType("char(10)");

                entity.HasOne(d => d.CountryCodeNavigation)
                    .WithMany(p => p.Customers)
                    .HasForeignKey(d => d.CountryCode)
                    .OnDelete(DeleteBehavior.Restrict)
                    .HasConstraintName("FK_Customers_Countries");
            });

            modelBuilder.Entity<EventSections>(entity =>
            {
                entity.HasKey(e => new { e.EventId, e.SectionId })
                    .HasName("PK__EventSec__414A3897F9A72D7B");

                entity.Property(e => e.Price).HasColumnType("money");

                entity.HasOne(d => d.Event)
                    .WithMany(p => p.EventSections)
                    .HasForeignKey(d => d.EventId)
                    .HasConstraintName("FK_EventSections_Events");

                entity.HasOne(d => d.Section)
                    .WithMany(p => p.EventSections)
                    .HasForeignKey(d => d.SectionId)
                    .OnDelete(DeleteBehavior.Restrict)
                    .HasConstraintName("FK_EventSections_Sections");
            });

            modelBuilder.Entity<Events>(entity =>
            {
                entity.HasKey(e => e.EventId)
                    .HasName("PK__Events__7944C81047DB4EF2");

                entity.Property(e => e.Date).HasColumnType("datetime");

                entity.Property(e => e.EventName)
                    .IsRequired()
                    .HasMaxLength(50);

                entity.Property(e => e.Subtitle).HasMaxLength(50);
            });

            modelBuilder.Entity<Sections>(entity =>
            {
                entity.HasKey(e => e.SectionId)
                    .HasName("PK__Sections__80EF0872FD27B716");

                entity.Property(e => e.SeatRows).HasDefaultValueSql("20");

                entity.Property(e => e.SeatsPerRow).HasDefaultValueSql("30");

                entity.Property(e => e.SectionName)
                    .IsRequired()
                    .HasMaxLength(30);

                entity.Property(e => e.StandardPrice)
                    .HasColumnType("money")
                    .HasDefaultValueSql("10");
            });

            modelBuilder.Entity<TicketPurchases>(entity =>
            {
                entity.HasKey(e => e.TicketPurchaseId)
                    .HasName("PK__TicketPu__97683DD692530887");

                entity.Property(e => e.PurchaseDate).HasColumnType("datetime");

                entity.Property(e => e.PurchaseTotal).HasColumnType("money");

                entity.HasOne(d => d.Customer)
                    .WithMany(p => p.TicketPurchases)
                    .HasForeignKey(d => d.CustomerId)
                    .OnDelete(DeleteBehavior.Restrict)
                    .HasConstraintName("FK_TicketPurchases_Customers");
            });

            modelBuilder.Entity<Tickets>(entity =>
            {
                entity.HasKey(e => e.TicketId)
                    .HasName("PK__Tickets__712CC60723C5191A");

                entity.HasIndex(e => new { e.EventId, e.SectionId, e.RowNumber, e.SeatNumber })
                    .HasName("IX_Tickets")
                    .IsUnique();

                entity.HasOne(d => d.TicketPurchase)
                    .WithMany(p => p.Tickets)
                    .HasForeignKey(d => d.TicketPurchaseId)
                    .HasConstraintName("FK_Tickets_TicketPurchases");

                entity.HasOne(d => d.EventSections)
                    .WithMany(p => p.Tickets)
                    .HasForeignKey(d => new { d.EventId, d.SectionId })
                    .OnDelete(DeleteBehavior.Restrict)
                    .HasConstraintName("FK_Tickets_EventSections");
            });

            modelBuilder.Entity<Venue>(entity =>
            {
                entity.HasKey(e => e.Lock)
                    .HasName("PK_Venue");

                entity.Property(e => e.Lock)
                    .HasColumnType("char(1)")
                    .HasDefaultValueSql("'X'");

                entity.Property(e => e.AdminEmail)
                    .IsRequired()
                    .HasColumnType("varchar(50)");

                entity.Property(e => e.AdminPassword).HasColumnType("nchar(30)");

                entity.Property(e => e.CountryCode)
                    .IsRequired()
                    .HasColumnType("char(3)");

                entity.Property(e => e.PostalCode).HasColumnType("char(10)");

                entity.Property(e => e.VenueName)
                    .IsRequired()
                    .HasMaxLength(50);

                entity.Property(e => e.VenueType)
                    .IsRequired()
                    .HasColumnType("char(30)");

                entity.HasOne(d => d.CountryCodeNavigation)
                    .WithMany(p => p.Venue)
                    .HasForeignKey(d => d.CountryCode)
                    .OnDelete(DeleteBehavior.Restrict)
                    .HasConstraintName("FK_Venues_Countries");

                entity.HasOne(d => d.VenueTypeNavigation)
                    .WithMany(p => p.Venue)
                    .HasForeignKey(d => d.VenueType)
                    .OnDelete(DeleteBehavior.Restrict)
                    .HasConstraintName("FK_Venues_VenueTypes");
            });

            modelBuilder.Entity<VenueTypes>(entity =>
            {
                entity.HasKey(e => e.VenueType)
                    .HasName("PK__VenueTyp__265E44FD9586CE48");

                entity.HasIndex(e => new { e.VenueTypeName, e.Language })
                    .HasName("IX_VENUETYPES_VENUETYPENAME_LANGUAGE")
                    .IsUnique();

                entity.Property(e => e.VenueType).HasColumnType("char(30)");

                entity.Property(e => e.EventTypeName)
                    .IsRequired()
                    .HasMaxLength(30);

                entity.Property(e => e.EventTypeShortName)
                    .IsRequired()
                    .HasMaxLength(20);

                entity.Property(e => e.EventTypeShortNamePlural)
                    .IsRequired()
                    .HasMaxLength(20);

                entity.Property(e => e.Language)
                    .IsRequired()
                    .HasColumnType("char(8)");

                entity.Property(e => e.VenueTypeName)
                    .IsRequired()
                    .HasColumnType("nchar(30)");
            });
        }
    }
}