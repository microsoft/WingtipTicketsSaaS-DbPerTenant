using System;
using System.Globalization;
using System.Linq;
using System.Threading;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;
using Events_TenantUserApp.ViewModels;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Localization;

namespace Events_TenantUserApp.Controllers
{
    [Route("{tenant}/FindSeats")]
    public class FindSeatsController: BaseController
    {
        private readonly IEventsRepository _eventsRepository;
        private readonly IEventSectionRepository _eventSectionRepository;
        private readonly ISectionRepository _sectionRepository;
        private readonly ITicketRepository _ticketRepository;
        private readonly ITicketPurchaseRepository _iTicketPurchaseRepository;
        private readonly IStringLocalizer<FindSeatsController> _localizer;
        private readonly string _connectionString;


        public FindSeatsController(IEventSectionRepository eventSectionRepository, ISectionRepository sectionRepository, IEventsRepository eventsRepository, ITicketRepository ticketRepository, ITicketPurchaseRepository ticketPurchaseRepository, IHelper helper, IStringLocalizer<FindSeatsController> localizer, IStringLocalizer<BaseController> baseLocalizer) : base(baseLocalizer, helper)
        {
            _eventSectionRepository = eventSectionRepository;
            _sectionRepository = sectionRepository;
            _eventsRepository = eventsRepository;
            _ticketRepository = ticketRepository;
            _iTicketPurchaseRepository = ticketPurchaseRepository;
            _localizer = localizer;

            Thread.CurrentThread.CurrentCulture = CultureInfo.CreateSpecificCulture(Startup.TenantConfig.TenantCulture);
            Thread.CurrentThread.CurrentUICulture = new CultureInfo(Startup.TenantConfig.TenantCulture);
            _connectionString = helper.GetBasicSqlConnectionString(Startup.DatabaseConfig);

        }

        [Route("FindSeats")]
        public ActionResult FindSeats(string tenant, int eventId)
        {
            if (eventId != 0)
            {
                SetTenantConfig(tenant);

                var eventDetails = _eventsRepository.GetEvent(eventId, _connectionString, Startup.TenantConfig.TenantId);

                if (eventDetails != null)
                {
                    var eventSections = _eventSectionRepository.GetEventSections(eventId, _connectionString, Startup.TenantConfig.TenantId);
                    var seatSectionIds = eventSections.Select(i => i.SectionId).ToList();

                    var seatSections = _sectionRepository.GetSections(seatSectionIds, _connectionString, Startup.TenantConfig.TenantId);
                    if (seatSections != null)
                    {
                        var ticketsSold = _ticketRepository.GetTicketsSold(seatSections[0].SectionId, eventId, _connectionString, Startup.TenantConfig.TenantId);

                        FindSeatViewModel viewModel = new FindSeatViewModel
                        {
                            EventDetails = eventDetails,
                            SeatSections = seatSections,
                            SeatsAvailable = (seatSections[0].SeatRows * seatSections[0].SeatsPerRow) - ticketsSold
                        };

                        return View(viewModel);
                    }
                }
            }
            return RedirectToAction("Index", "Events", new { tenant = Startup.TenantConfig.TenantName });
        }

        [Route("GetAvailableSeats")]
        public ActionResult GetAvailableSeats(string tenant, int sectionId, int eventId)
        {
            SetTenantConfig(tenant);

            var sectionDetails = _sectionRepository.GetSection(sectionId, _connectionString, Startup.TenantConfig.TenantId);
            var totalNumberOfSeats = sectionDetails.SeatRows * sectionDetails.SeatsPerRow;
            var ticketsSold = _ticketRepository.GetTicketsSold(sectionId, eventId, _connectionString, Startup.TenantConfig.TenantId);

            var availableSeats = totalNumberOfSeats - ticketsSold;
            return Content(availableSeats.ToString());
        }


        [HttpPost]
        [Route("PurchaseTickets")]
        public ActionResult PurchaseTickets(string tenant, string eventId, string customerId, string ticketPrice, string ticketCount, string sectionId)
        {
            bool purchaseResult = false;
            int numberOfTickets = Convert.ToInt32(ticketCount);

            if (string.IsNullOrEmpty(eventId) || string.IsNullOrEmpty(customerId) || string.IsNullOrEmpty(ticketPrice) || string.IsNullOrEmpty(ticketCount))
            {
                var message = _localizer["Enter quantity"];
                DisplayMessage(message, "Confirmation");
                return RedirectToAction("Index", "Events", new { tenant = Startup.TenantConfig.TenantName });
            }

            var ticketPurchaseModel = new TicketPurchaseModel
            {
                CustomerId = Convert.ToInt32(customerId),
                PurchaseTotal = Convert.ToDecimal(ticketPrice)
            };

            SetTenantConfig(tenant);

            var latestPurchaseTicketId = _iTicketPurchaseRepository.GetNumberOfTicketPurchases(_connectionString, Startup.TenantConfig.TenantId);
            ticketPurchaseModel.TicketPurchaseId = latestPurchaseTicketId + 1;

            var purchaseTicketId = _iTicketPurchaseRepository.Add(ticketPurchaseModel, _connectionString, Startup.TenantConfig.TenantId);

            var ticketModel = new TicketModel
            {
                SectionId = Convert.ToInt32(sectionId),
                EventId = Convert.ToInt32(eventId),
                TicketPurchaseId = purchaseTicketId
            };

            Random rnd = new Random();
            for (var i = 0; i < numberOfTickets; i++)
            {
                Random rnd2 = new Random(5000);
                ticketModel.RowNumber = rnd.Next(0, 100000);
                ticketModel.SeatNumber = rnd2.Next(0, 100000);
               purchaseResult = _ticketRepository.Add(ticketModel, _connectionString, Startup.TenantConfig.TenantId);
            }

            var successMessage = _localizer[$"You have successfully purchased {ticketCount} tickets."];
            var failureMessage = _localizer["Failed to purchase tickets."];

            if (purchaseResult)
            {
                DisplayMessage(successMessage, "Confirmation");
            }
            else
            {
                DisplayMessage(failureMessage, "Error");
            }

            return RedirectToAction("Index", "Events", new { tenant = Startup.TenantConfig.TenantName });
        }
    }
}
