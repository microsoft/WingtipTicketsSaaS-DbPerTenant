using System.Globalization;
using System.Threading;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Microsoft.AspNetCore.Mvc;

namespace Events_TenantUserApp.Controllers
{
    public class EventsController : Controller
    {
        #region Fields
        private readonly ITenantsRepository _tenantsRepository;
        private readonly IVenuesRepository _venuesRepository;
        private readonly IEventsRepository _eventsRepository;
        private readonly IVenueTypesRepository _venueTypesRepository;
        private readonly ICountryRepository _countryRepository;
        private readonly IHelper _helper;
        #endregion

        #region Constructors

        public EventsController(ITenantsRepository tenantsRepository, IVenuesRepository venuesRepository, IEventsRepository eventsRepository, IVenueTypesRepository venueTypesRepository, ICountryRepository countryRepository, IHelper helper)
        {
            _tenantsRepository = tenantsRepository;
            _venuesRepository = venuesRepository;
            _eventsRepository = eventsRepository;
            _venueTypesRepository = venueTypesRepository;
            _countryRepository = countryRepository;
            _helper = helper;
        }
        #endregion


        [Route("{tenant}")]
        public ActionResult Index(string tenant)
        {
            //get the tenantId from tenant catalog
            var tenantDetails = _tenantsRepository.GetTenant(tenant);
            var connectionString = _helper.GetSqlConnectionString(Startup.DatabaseConfig);

            if (tenantDetails != null)
            {
                //get the venue details and populate in config settings
                var venueDetails = _venuesRepository.GetVenueDetails(connectionString, tenantDetails.TenantId);
                var venueTypeDetails = _venueTypesRepository.GetVenueType(venueDetails.VenueType, connectionString, tenantDetails.TenantId);
                var countries = _countryRepository.GetAllCountries(connectionString, tenantDetails.TenantId);

                if (venueTypeDetails != null)
                {
                    Startup.TenantConfig = _helper.PopulateTenantConfigs(tenant, Startup.TenantConfig, Startup.DatabaseConfig, venueDetails, venueTypeDetails, tenantDetails, countries);

                    var events = _eventsRepository.GetEventsForTenant(connectionString, Startup.TenantConfig.TenantId);

                    //localisation per venue's language
                    var culture = venueTypeDetails.Language;
                    if (!string.IsNullOrEmpty(culture))
                    {
                        Thread.CurrentThread.CurrentCulture = CultureInfo.CreateSpecificCulture(culture);
                        Thread.CurrentThread.CurrentUICulture = new CultureInfo(culture);
                    }
                    return View(events);
                }
            }
            return View("Error");
        }
    }
}
