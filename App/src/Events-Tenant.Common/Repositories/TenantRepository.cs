using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Linq;
using System.Threading.Tasks;
using Events_Tenant.Common.Interfaces;
using Events_Tenant.Common.Mapping;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;
using Events_TenantUserApp.EF.TenantsDB;
using Microsoft.EntityFrameworkCore;
using Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement;

namespace Events_Tenant.Common.Repositories
{
    public class TenantRepository : ITenantRepository
    {
        #region Private variables

        private readonly string _connectionString;

        #endregion

        #region Constructor

        public TenantRepository(string connectionString)
        {
            _connectionString = connectionString;
        }

        #endregion

        #region Countries

        public async Task<List<CountryModel>> GetAllCountries(int tenantId)
        {
            using (var context = CreateContext(tenantId))
            {
                var allCountries = await context.Countries.ToListAsync();

                return allCountries.Count > 0 ? allCountries.Select(country => country.ToCountryModel()).ToList() : null;
            }
        }

        public async Task<CountryModel> GetCountry(string countryCode, int tenantId)
        {
            using (var context = CreateContext(tenantId))
            {
                var country = await context.Countries.FirstOrDefaultAsync(x => x.CountryCode == countryCode);
                return country?.ToCountryModel();
            }
        }

        #endregion

        #region Customers

        public async Task<int> AddCustomer(CustomerModel customeModel, int tenantId)
        {
            using (var context = CreateContext(tenantId))
            {
                var customer = customeModel.ToCustomersEntity();

                context.Customers.Add(customer);
                await context.SaveChangesAsync();

                return customer.CustomerId;
            }
        }

        public async Task<CustomerModel> GetCustomer(string email, int tenantId)
        {
            using (var context = CreateContext(tenantId))
            {
                var customer = await context.Customers.FirstOrDefaultAsync(i => i.Email == email);

                return customer?.ToCustomerModel();
            }
        }

        #endregion

        #region EventSections

        public async Task<List<EventSectionModel>> GetEventSections(int eventId, int tenantId)
        {
            using (var context = CreateContext(tenantId))
            {
                var eventsections = await context.EventSections.Where(i => i.EventId == eventId).ToListAsync();

                return eventsections.Count > 0 ? eventsections.Select(eventSection => eventSection.ToEventSectionModel()).ToList() : null;
            }
        }

        #endregion

        #region Events

        public async Task<List<EventModel>> GetEventsForTenant(int tenantId)
        {
            using (var context = CreateContext(tenantId))
            {
                //Past events (yesterday and earlier) are not shown 
                var events = await context.Events.Where(i => i.Date >= DateTime.Now).OrderBy(x => x.Date).ToListAsync();

                return events.Count > 0 ? events.Select(eventEntity => eventEntity.ToEventModel()).ToList() : null;
            }
        }

        public async Task<EventModel> GetEvent(int eventId, int tenantId)
        {
            using (var context = CreateContext(tenantId))
            {
                var eventModel = await context.Events.FirstOrDefaultAsync(i => i.EventId == eventId);

                return eventModel?.ToEventModel();
            }
        }

        #endregion

        #region Sections

        public async Task<List<SectionModel>> GetSections(List<int> sectionIds, int tenantId)
        {
            using (var context = CreateContext(tenantId))
            {
                var sections = await context.Sections.Where(i => sectionIds.Contains(i.SectionId)).ToListAsync();

                return sections.Any() ? sections.Select(section => section.ToSectionModel()).ToList() : null;
            }
        }

        public async Task<SectionModel> GetSection(int sectionId, int tenantId)
        {
            using (var context = CreateContext(tenantId))
            {
                var section = await context.Sections.FirstOrDefaultAsync(i => i.SectionId == sectionId);

                return section?.ToSectionModel();
            }
        }

        #endregion

        #region TicketPurchases

        public async Task<int> AddTicketPurchase(TicketPurchaseModel ticketPurchaseModel, int tenantId)
        {
            using (var context = CreateContext(tenantId))
            {
                var ticketPurchase = ticketPurchaseModel.ToTicketPurchasesEntity();

                context.TicketPurchases.Add(ticketPurchase);
                await context.SaveChangesAsync();

                return ticketPurchase.TicketPurchaseId;
            }
        }

        #endregion

        #region Tickets

        public async Task<bool> AddTickets(List<TicketModel> ticketModels, int tenantId)
        {
            using (var context = CreateContext(tenantId))
            {
                foreach (TicketModel ticketModel in ticketModels)
                {
                    context.Tickets.Add(ticketModel.ToTicketsEntity());
                }
                await context.SaveChangesAsync();
            }
            return true;
        }

        public async Task<int> GetTicketsSold(int sectionId, int eventId, int tenantId)
        {
            using (var context = CreateContext(tenantId))
            {
                var tickets = await context.Tickets.Where(i => i.SectionId == sectionId && i.EventId == eventId).ToListAsync();
                if (tickets.Any())
                {
                    return tickets.Count();
                }
            }
            return 0;
        }

        #endregion

        #region Venues

        public async Task<VenueModel> GetVenueDetails(int tenantId)
        {
            using (var context = CreateContext(tenantId))
            {
                //get database name
                string databaseName, databaseServerName;
                PointMapping<int> mapping;

                if (Sharding.ShardMap.TryGetMappingForKey(tenantId, out mapping))
                {
                    using (SqlConnection sqlConn = Sharding.ShardMap.OpenConnectionForKey(tenantId, _connectionString))
                    {
                        databaseName = sqlConn.Database;
                        databaseServerName = sqlConn.DataSource.Split(':').Last().Split(',').First();
                    }

                    var venue = await context.Venue.FirstOrDefaultAsync();

                    if (venue != null)
                    {
                        var venueModel = venue.ToVenueModel();
                        venueModel.DatabaseName = databaseName;
                        venueModel.DatabaseServerName = databaseServerName;
                        return venueModel;
                    }
                }
                return null;
            }
        }

        #endregion

        #region VenueTypes

        public async Task<VenueTypeModel> GetVenueType(string venueType, int tenantId)
        {
            using (var context = CreateContext(tenantId))
            {
                var venueTypeDetails = await context.VenueTypes.FirstOrDefaultAsync(i => i.VenueType == venueType);

                return venueTypeDetails?.ToVenueTypeModel();
            }
        }

        #endregion

        #region Private methods
        private TenantDbContext CreateContext(int tenantId)
        {
            return new TenantDbContext(Sharding.ShardMap, tenantId, _connectionString);
        }
        #endregion
    }
}
