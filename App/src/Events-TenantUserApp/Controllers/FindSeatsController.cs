using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Events_Tenant.Common.Interfaces;
using Events_Tenant.Common.Models;
using Events_TenantUserApp.ViewModels;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Localization;
using Microsoft.Extensions.Logging;

namespace Events_TenantUserApp.Controllers
{
    [Route("{tenant}/FindSeats")]
    public class FindSeatsController : BaseController
    {
        #region Private varibles

        private readonly ITenantRepository _tenantRepository;
        private readonly ICatalogRepository _catalogRepository;
        private readonly IStringLocalizer<FindSeatsController> _localizer;
        private readonly ILogger _logger;
        private readonly DnsClient.ILookupClient _client;

        #endregion

        #region Constructor

        public FindSeatsController(ITenantRepository tenantRepository, ICatalogRepository catalogRepository, IStringLocalizer<FindSeatsController> localizer, IStringLocalizer<BaseController> baseLocalizer, ILogger<FindSeatsController> logger, IConfiguration configuration, DnsClient.ILookupClient client) : base(baseLocalizer, tenantRepository, configuration, client)
        {
            _tenantRepository = tenantRepository;
            _catalogRepository = catalogRepository;
            _localizer = localizer;
            _logger = logger;
            _client = client;
        }

        #endregion

        [Route("FindSeats")]
        public async Task<ActionResult> FindSeats(string tenant, int eventId)
        {
            try
            {
                if (eventId != 0)
                {
                    var tenantDetails = (_catalogRepository.GetTenant(tenant)).Result;
                    if (tenantDetails != null)
                    {
                        SetTenantConfig(tenantDetails.TenantId, tenantDetails.TenantIdInString);

                        var eventDetails = await _tenantRepository.GetEvent(eventId, tenantDetails.TenantId);

                        if (eventDetails != null)
                        {
                            var eventSections = await _tenantRepository.GetEventSections(eventId, tenantDetails.TenantId);
                            var seatSectionIds = eventSections.Select(i => i.SectionId).ToList();

                            var seatSections = await _tenantRepository.GetSections(seatSectionIds, tenantDetails.TenantId);
                            if (seatSections != null)
                            {
                                var ticketsSold = await _tenantRepository.GetTicketsSold(seatSections[0].SectionId, eventId, tenantDetails.TenantId);

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
                    else
                    {
                        return View("TenantError", tenant);
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(0, ex, "FindSeats failed for tenant {tenant} and event {eventId}", tenant, eventId);
                return View("TenantError", tenant);
            }
            return RedirectToAction("Index", "Events", new { tenant });
        }

        [Route("GetAvailableSeats")]
        public async Task<ActionResult> GetAvailableSeats(string tenant, int sectionId, int eventId)
        {
            try
            {
                var tenantDetails = (_catalogRepository.GetTenant(tenant)).Result;
                if (tenantDetails != null)
                {
                    SetTenantConfig(tenantDetails.TenantId, tenantDetails.TenantIdInString);

                    var sectionDetails = await _tenantRepository.GetSection(sectionId, tenantDetails.TenantId);
                    var totalNumberOfSeats = sectionDetails.SeatRows * sectionDetails.SeatsPerRow;
                    var ticketsSold = await _tenantRepository.GetTicketsSold(sectionId, eventId, tenantDetails.TenantId);

                    var availableSeats = totalNumberOfSeats - ticketsSold;
                    return Content(availableSeats.ToString());
                }
                else
                {
                    return View("TenantError", tenant);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(0, ex, "GetAvailableSeats failed for tenant {tenant} and event {eventId}", tenant, eventId);
                return Content("0");
            }
        }

        [HttpPost]
        [Route("PurchaseTickets")]
        public async Task<ActionResult> PurchaseTickets(string tenant, int eventId, int customerId, decimal ticketPrice, int ticketCount, int sectionId)
        {
            try
            {
                bool purchaseResult = false;

                var ticketPurchaseModel = new TicketPurchaseModel
                {
                    CustomerId = customerId,
                    PurchaseTotal = ticketPrice
                };

                var tenantDetails = (_catalogRepository.GetTenant(tenant)).Result;
                if (tenantDetails != null)
                {
                    SetTenantConfig(tenantDetails.TenantId, tenantDetails.TenantIdInString);

                    var purchaseTicketId = await _tenantRepository.AddTicketPurchase(ticketPurchaseModel, tenantDetails.TenantId);

                    List<TicketModel> ticketsModel = BuildTicketModel(eventId, sectionId, ticketCount, purchaseTicketId);
                    purchaseResult = await _tenantRepository.AddTickets(ticketsModel, tenantDetails.TenantId);

                    if (purchaseResult)
                        DisplayMessage(_localizer[$"You have successfully purchased {ticketCount} ticket(s)."], "Confirmation");
                    else
                        DisplayMessage(_localizer["Failed to purchase tickets."], "Error");
                }
                else
                {
                    return View("TenantError", tenant);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(0, ex, "Purchase tickets failed for tenant {tenant} and event {eventId}", tenant, eventId);
                return View("TenantError", tenant);
            }
            return RedirectToAction("Index", "Events", new { tenant });

        }
    }
}
