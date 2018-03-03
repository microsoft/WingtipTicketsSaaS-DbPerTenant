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
        private readonly IUtilities _utilities;

        #endregion

        #region Constructors

        /// <summary>
        /// Initializes a new instance of the <see cref="HomeController" /> class.
        /// </summary>
        /// <param name="catalogRepository">The tenants repository.</param>
        /// <param name="tenantRepository">The venues repository.</param>
        /// <param name="logger">The logger.</param>
        /// <param name="utilities">The utilities class.</param>
        public HomeController(ICatalogRepository catalogRepository, ITenantRepository tenantRepository, ILogger<HomeController> logger, IUtilities utilities)
        {
            _catalogRepository = catalogRepository;
            _tenantRepository = tenantRepository;
            _logger = logger;
            _utilities = utilities;
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
                            if (ex.ErrorCode == Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardManagementErrorCode.MappingIsOffline)
                            {
                                _logger.LogInformation(0, ex, "Tenant is offline: {tenant}", tenant.TenantName);                       
                            }
                            else if (ex.ErrorCode == Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardManagementErrorCode.MappingDoesNotExist)
                            {
                                //Fix mapping irregularities
                                _utilities.ResolveMappingDifferences(tenant.TenantId);

                                //Get venue details
                                String tenantStatus = _utilities.GetTenantStatus(tenant.TenantId);
                                if (tenantStatus == "Online")
                                {
                                    venue = await _tenantRepository.GetVenueDetails(tenant.TenantId);
                                }
                            }
                            else
                            {
                                _logger.LogError(0, ex.Message, "Mapping unavailable for tenant: {tenant}", tenant.TenantName);
                            }                                                    
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
