using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Events_Tenant.Common.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Tests.MockRepositories
{
    public class MockTenantRepository : ITenantRepository
    {
        #region Private Variables
        private List<CountryModel> Countries { get; set; }
        private CustomerModel CustomerModel { get; set; }
        #endregion

        #region Public Properties

        public List<EventSectionModel> EventSectionModels { get; set; }
        public List<SectionModel> SectionModels { get; set; }
        public List<TicketPurchaseModel> TicketPurchaseModels { get; set; }
        public List<TicketModel> TicketModels { get; set; }
        public List<EventModel> EventModels { get; set; }
        #endregion

        public MockTenantRepository()
        {
            var country = new CountryModel
            {
                Language = "en-us",
                CountryCode = "USA",
                CountryName = "United States"
            };
            Countries = new List<CountryModel> { country };

            EventSectionModels = new List<EventSectionModel>
            {
                new EventSectionModel
                {
                    SectionId = 1,
                    EventId = 1,
                    Price = 100
                },
                new EventSectionModel
                {
                    SectionId = 2,
                    EventId = 1,
                    Price = 80
                },
                new EventSectionModel
                {
                    SectionId = 3,
                    EventId = 1,
                    Price = 60
                }
            };

            SectionModels = new List<SectionModel>
            {
                new SectionModel
                {
                    SectionId = 1,
                    SeatsPerRow = 10,
                    SectionName = "section 1",
                    StandardPrice = 100,
                    SeatRows = 4
                },
                new SectionModel
                {
                    SectionId = 2,
                    SeatsPerRow = 20,
                    SectionName = "section 2",
                    StandardPrice = 80,
                    SeatRows = 5
                }
            };

            TicketPurchaseModels = new List<TicketPurchaseModel>
            {
                new TicketPurchaseModel
                {
                    CustomerId = 1,
                    PurchaseTotal = 2,
                    TicketPurchaseId = 5,
                    PurchaseDate = DateTime.Now
                }
            };

            TicketModels = new List<TicketModel>
            {
                new TicketModel
                {
                    SectionId = 1,
                    EventId = 1,
                    TicketPurchaseId = 12,
                    SeatNumber = 50,
                    RowNumber = 2,
                    TicketId = 2
                }
            };

            EventModels = new List<EventModel>
            {
                new EventModel
                {
                    EventId = 1,
                    EventName = "Event 1",
                    Date = DateTime.Now,
                    SubTitle = "Event 1 Subtitle"
                },
                new EventModel
                {
                    EventId = 2,
                    EventName = "Event 2",
                    Date = DateTime.Now,
                    SubTitle = "Event 2 Subtitle"
                }
            };
        }

        public async Task<List<CountryModel>> GetAllCountries(int tenantId)
        {
            return Countries;
        }

        public async Task<CountryModel> GetCountry(string countryCode, int tenantId)
        {
            return Countries[0];
        }

        public async Task<int> AddCustomer(CustomerModel customerModel, int tenantId)
        {
            CustomerModel = customerModel;
            return 123;
        }

        public async Task<CustomerModel> GetCustomer(string email, int tenantId)
        {
            return CustomerModel;
        }

        public async Task<List<EventSectionModel>> GetEventSections(int eventId, int tenantId)
        {
            return EventSectionModels;
        }

        public async Task<List<SectionModel>> GetSections(List<int> sectionIds, int tenantId)
        {
            return SectionModels;
        }

        public async Task<SectionModel> GetSection(int sectionId, int tenantId)
        {
            return SectionModels[0];
        }

        public async Task<int> AddTicketPurchase(TicketPurchaseModel ticketPurchaseModel, int tenantId)
        {
            TicketPurchaseModels.Add(ticketPurchaseModel);
            return ticketPurchaseModel.TicketPurchaseId;
        }

        public async Task<bool> AddTickets(List<TicketModel> ticketModels, int tenantId)
        {
            foreach (TicketModel ticketModel in ticketModels)
            {
                TicketModels.Add(ticketModel);
            }
            return true;
        }

        public async Task<int> GetTicketsSold(int sectionId, int eventId, int tenantId)
        {
            return TicketModels.Count;
        }

        public async Task<VenueModel> GetVenueDetails(int tenantId)
        {
            return new VenueModel
            {
                CountryCode = "USA",
                VenueType = "pop",
                VenueName = "Venue 1",
                PostalCode = "123",
                AdminEmail = "admin@email.com",
                AdminPassword = "password"
            };
        }

        public async Task<VenueTypeModel> GetVenueType(string venueType, int tenantId)
        {
            return new VenueTypeModel
            {
                Language = "en-us",
                VenueType = "pop",
                EventTypeShortNamePlural = "event short name",
                EventTypeName = "classic",
                VenueTypeName = "type 1",
                EventTypeShortName = "short name"
            };
        }

        public async Task<List<EventModel>> GetEventsForTenant(int tenantId)
        {
            return EventModels;
        }

        public async Task<EventModel> GetEvent(int eventId, int tenantId)
        {
            return EventModels[0];
        }

    }
}