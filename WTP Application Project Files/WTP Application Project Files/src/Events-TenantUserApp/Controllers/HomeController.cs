using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Events_TenantUserApp.Controllers
{
    public class HomeController : Controller
    {
        #region - Fields -

        private readonly ITenantsRepository _tenantsRepository;
        private readonly IVenuesRepository _venuesRepository;
        private readonly IEventsRepository _eventsRepository;
        private readonly IHttpContextAccessor _httpContextAccessor;


        #endregion

        #region - Constructors -

        /// <summary>
        /// Initializes a new instance of the <see cref="HomeController" /> class.
        /// </summary>
        /// <param name="tenantsRepository">The tenants repository.</param>
        /// <param name="venuesRepository">The venues repository.</param>
        /// <param name="eventsRepository">The events repository.</param>
        /// <param name="httpContextAccessor">The HTTP context accessor.</param>
        public HomeController(ITenantsRepository tenantsRepository, IVenuesRepository venuesRepository, IEventsRepository eventsRepository, IHttpContextAccessor httpContextAccessor)
        {
            _httpContextAccessor = httpContextAccessor;
            _tenantsRepository = tenantsRepository;
            _venuesRepository = venuesRepository;
            _eventsRepository = eventsRepository;

            //if (!_httpContextAccessor.HttpContext.Items.ContainsKey("TenantInfo"))
            //{
            //     RequestInitialization.InitializeTenantConfig();
            //}


        }

        #endregion


        /// <summary>
        /// This method is hit when not passing any tenant name
        /// Will display the Events Hub page
        /// </summary>
        /// <returns></returns>
        public IActionResult Index()
        {
            var tenantsModel = _tenantsRepository.GetAllTenants(Startup.CustomerCatalogConfig, Startup.DatabaseConfig);

            //get the venue name for each tenant
            foreach (var tenant in tenantsModel)
            {
                VenueModel venue = _venuesRepository.GetVenueDetails(tenant.TenantId, Startup.DatabaseConfig, Startup.TenantServerConfig);
                tenant.VenueName = venue.VenueName;
            }

            //return View(tenantsModel);
            return View(tenantsModel);
        }

        /// <summary>
        /// This method will be hit when passing a tenant name
        /// and will go directly to events browse page
        /// </summary>
        /// <param name="tenantName">Name of the tenant.</param>
        /// <returns></returns>
        [Route("{tenantName}")]
        public ActionResult Index(string tenantName)
        {
            //todo: handle if request is coming from events hub or directly from app url
           
            //get the tenantId from tenant catalog
            var tenantDetails = _tenantsRepository.GetTenant(tenantName, Startup.CustomerCatalogConfig, Startup.DatabaseConfig);

            var events = _eventsRepository.GetEventsForTenant(tenantDetails.TenantId, Startup.DatabaseConfig, Startup.TenantServerConfig);

            return View();
        }

        public IActionResult GetVenueDetails()
        {
            //get tenant name


            return View();
        }

        public IActionResult About()
        {
            ViewData["Message"] = "Your application description page.";

            return View();
        }

        public IActionResult Contact()
        {
            ViewData["Message"] = "Your contact page.";

            return View();
        }

        public IActionResult Error()
        {
            return View();
        }
    }
}
