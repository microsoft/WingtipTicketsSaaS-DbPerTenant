using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Utilities;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Localization;

namespace Events_TenantUserApp.Controllers
{
    public class EventsController : BaseController
    {
        #region Fields
        private readonly IEventsRepository _eventsRepository;
        private readonly IHelper _helper;
        private static readonly object _lock = new object();

        #endregion

        #region Constructors

        public EventsController(IEventsRepository eventsRepository, IMemoryCache memoryCache, IStringLocalizer<BaseController> baseLocalizer, IHelper helper) : base(baseLocalizer, memoryCache, helper)
        {
            _eventsRepository = eventsRepository;
            _helper = helper;
        }

        #endregion


        [Route("{tenant}")]
        public ActionResult Index(string tenant)
        {
            lock (_lock)
            {
                var connectionString = _helper.GetBasicSqlConnectionString(Startup.DatabaseConfig);
                if (!string.IsNullOrEmpty(tenant))
                {
                    if (string.IsNullOrEmpty(Startup.TenantConfig.TenantName) || tenant != Startup.TenantConfig.TenantName)
                    {
                        SetTenantConfig(tenant);
                    }

                    var events = _eventsRepository.GetEventsForTenant(connectionString, Startup.TenantConfig.TenantId);

                    return View(events);
                }

                return View("Error");

            }
        }
    }
}

