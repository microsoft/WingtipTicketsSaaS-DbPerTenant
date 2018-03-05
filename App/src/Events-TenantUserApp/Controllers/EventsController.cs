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
        private readonly IUtilities _utilities;
        private String _appRegion;
        #endregion

        #region Constructors

        public EventsController(ITenantRepository tenantRepository, ICatalogRepository catalogRepository, IStringLocalizer<BaseController> baseLocalizer, ILogger<EventsController> logger, IConfiguration configuration, DnsClient.ILookupClient client, IUtilities utilities) : base(baseLocalizer, tenantRepository, configuration, client)
        {
            _logger = logger;
            _tenantRepository = tenantRepository;
            _catalogRepository = catalogRepository;
            _client = client;
            _utilities = utilities;
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

                        //Get tenant status
                        String tenantStatus = _utilities.GetTenantStatus(tenantDetails.TenantId);

                        if ((tenantServerName.Contains(_appRegion)) && (tenantStatus == "Online"))
                        {
                            SetTenantConfig(tenantDetails.TenantId, tenantDetails.TenantIdInString);

                            var events = await _tenantRepository.GetEventsForTenant(tenantDetails.TenantId);
                            return View(events);
                        }
                        else if (tenantStatus == "Offline")
                        {
                            return View("TenantOffline", tenantDetails.TenantName);
                        }                                
                        else
                        {
                            var pairedRegion = (tenantServerName.Split('-'))[0].Split('1')[0];
                            String recoveryAppInstance = "https://events-wingtip-dpt-" + pairedRegion + "-" + _configuration["User"] + ".azurewebsites.net/" + tenant;
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
                else if (ex.ErrorCode == Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardManagementErrorCode.MappingDoesNotExist)
                {
                    var tenantModel = await _catalogRepository.GetTenant(tenant);
                    //Fix mapping irregularities
                    _utilities.ResolveMappingDifferences(tenantModel.TenantId);

                    //Get venue details
                    String tenantStatus = _utilities.GetTenantStatus(tenantModel.TenantId);
                    if (tenantStatus == "Online")
                    {
                        var events = await _tenantRepository.GetEventsForTenant(tenantModel.TenantId);
                        return View(events);
                    }
                    else
                    {
                        return View("TenantOffline", tenantModel.TenantName);
                    }
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

