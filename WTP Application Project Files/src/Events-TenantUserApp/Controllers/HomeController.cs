using System;
using System.Threading.Tasks;
using Events_Tenant.Common.Interfaces;
using Events_Tenant.Common.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace Events_TenantUserApp.Controllers
{
    public class HomeController : Controller
    {
        #region Fields

        private readonly ICatalogRepository _catalogRepository;
        private readonly ITenantRepository _tenantRepository;
        private readonly ILogger _logger;

        #endregion

        #region Constructors

        /// <summary>
        /// Initializes a new instance of the <see cref="HomeController" /> class.
        /// </summary>
        /// <param name="catalogRepository">The tenants repository.</param>
        /// <param name="tenantRepository">The venues repository.</param>
        /// <param name="logger">The logger.</param>
        public HomeController(ICatalogRepository catalogRepository, ITenantRepository tenantRepository, ILogger<HomeController> logger)
        {
            _catalogRepository = catalogRepository;
            _tenantRepository = tenantRepository;
            _logger = logger;
        }

        #endregion

        /// <summary>
        /// This method is hit when not passing any tenant name
        /// Will display the Events Hub page
        /// </summary>
        /// <returns></returns>
        public async Task<IActionResult> Index()
        {
            try
            {
                var tenantsModel = await _catalogRepository.GetAllTenants();

                if (tenantsModel != null)
                {
                    //get the venue name for each tenant
                    foreach (var tenant in tenantsModel)
                    {
                        VenueModel venue = null;
                        try
                        {
                            venue = await _tenantRepository.GetVenueDetails(tenant.TenantId);
                        }
                        catch (Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardManagementException ex)
                        {
                            _logger.LogError(0, ex, "Tenant '" + tenant.TenantName + "' is unavailable in the catalog");                           
                        }
                                                    
                        if (venue != null)
                        {
                            tenant.VenueName = venue.VenueName;
                            tenant.TenantName = venue.DatabaseName;
                        }

                    }
                    return View(tenantsModel);
                }
            }            
            catch (Exception ex)
            {
                _logger.LogError(0, ex, "Error in getting all tenants in Events Hub");
                return View("Error", ex.Message);              
            }
            return View("Error");  

        }

        public IActionResult Error()
        {
            return View();
        }
    }
}
