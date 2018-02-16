using System;
using System.Threading.Tasks;
using Events_Tenant.Common.Interfaces;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Localization;
using Microsoft.Extensions.Logging;
using System.Linq;

namespace Events_TenantUserApp.Controllers
{
    public class EventsController : BaseController
    {
        #region Fields
        private readonly ITenantRepository _tenantRepository;
        private readonly ICatalogRepository _catalogRepository;
        private readonly ILogger _logger;
        private readonly DnsClient.ILookupClient _client;
        private readonly IConfiguration _configuration;
        private String _appRegion;
        #endregion

        #region Constructors

        public EventsController(ITenantRepository tenantRepository, ICatalogRepository catalogRepository, IStringLocalizer<BaseController> baseLocalizer, ILogger<EventsController> logger, IConfiguration configuration, DnsClient.ILookupClient client) : base(baseLocalizer, tenantRepository, configuration, client)
        {
            _logger = logger;
            _tenantRepository = tenantRepository;
            _catalogRepository = catalogRepository;
            _client = client;
            _configuration = configuration;
            _appRegion = configuration["APP_REGION"];
        }

        #endregion


        [Route("{tenant}")]
        public async Task<ActionResult> Index(string tenant)
        {
            try
            {
                if (!string.IsNullOrEmpty(tenant))
                {
                    var tenantDetails = await _catalogRepository.GetTenant(tenant);
                    if (tenantDetails != null)
                    {
                        //get tenant servername from tenant alias
                        var serverAliases = _client.Query(tenantDetails.TenantAlias, DnsClient.QueryType.A);
                        String tenantServerName = serverAliases.Answers.ARecords().ElementAt(0).DomainName;

                        if (tenantServerName.Contains(_appRegion))
                        {
                            SetTenantConfig(tenantDetails.TenantId, tenantDetails.TenantIdInString);

                            var events = await _tenantRepository.GetEventsForTenant(tenantDetails.TenantId);
                            return View(events);
                        }                                  
                        else
                        {
                            String recoveryAppInstance = "https://events-wingtip-dpt-" + _appRegion + "-" + _configuration["User"] + ".azurewebsites.net/" + tenant;
                            return Redirect(recoveryAppInstance);
                        }
                    }
                    else
                    {
                        return View("TenantError", tenant);
                    }
                }
            }
            catch (Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardManagementException ex)
            {
                if (ex.ErrorCode == Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardManagementErrorCode.MappingIsOffline)
                {
                    var tenantModel = await _catalogRepository.GetTenant(tenant);
                    _logger.LogInformation(0, ex, "Tenant is offline: {tenant}", tenantModel.TenantName);
                    return View("TenantOffline", tenantModel.TenantName);
                }
                else
                {
                    _logger.LogError(0, ex, "Tenant shard was unavailable for tenant: {tenant}", tenant);
                    return View("Error", ex.Message);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(0, ex, "Get events failed for tenant {tenant}", tenant);
                return View("Error", ex.Message);
            }
            return View("Error");
        }
    }
}

