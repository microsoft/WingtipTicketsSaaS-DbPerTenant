using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Models;
using Microsoft.AspNetCore.Mvc;

namespace Events_TenantUserApp.Controllers
{
    public class HomeController : Controller
    {
        #region Fields

        private readonly ITenantsRepository _tenantsRepository;
        private readonly IVenuesRepository _venuesRepository;
        private readonly string _connectionString;

        #endregion

        #region Constructors

        /// <summary>
        /// Initializes a new instance of the <see cref="HomeController" /> class.
        /// </summary>
        /// <param name="tenantsRepository">The tenants repository.</param>
        /// <param name="venuesRepository">The venues repository.</param>
        /// <param name="helper">The helper class</param>
        public HomeController(ITenantsRepository tenantsRepository, IVenuesRepository venuesRepository, IHelper helper)
        {
            _tenantsRepository = tenantsRepository;
            _venuesRepository = venuesRepository;
            _connectionString = helper.GetSqlConnectionString(Startup.DatabaseConfig);
        }

        #endregion


        /// <summary>
        /// This method is hit when not passing any tenant name
        /// Will display the Events Hub page
        /// </summary>
        /// <returns></returns>
        public IActionResult Index()
        {
            var tenantsModel = _tenantsRepository.GetAllTenants();

            //get the venue name for each tenant
            foreach (var tenant in tenantsModel)
            {
                VenueModel venue = _venuesRepository.GetVenueDetails(_connectionString, tenant.TenantId);
                tenant.VenueName = venue.VenueName;
            }

            return View(tenantsModel);
        }

        /// <summary>
        /// This method will be hit when passing a tenant name
        /// and will redirect to the events controller
        /// </summary>
        /// <param name="tenantName">Name of the tenant.</param>
        /// <returns></returns>
        [Route("{tenantName}")]
        public ActionResult Index(string tenantName)
        {
            return RedirectToAction("Index", "Events", new {tenant = tenantName});
        }


        public IActionResult Error()
        {
            return View();
        }
    }
}
