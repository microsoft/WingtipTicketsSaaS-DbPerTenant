using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Localization;

namespace Events_TenantUserApp.Controllers
{
    public class EventsController : BaseController
    {
        #region Fields
        private readonly IEventsRepository _eventsRepository;
        private readonly IHelper _helper;
        private static readonly object Lock = new object();

        #endregion

        #region Constructors

        public EventsController(IEventsRepository eventsRepository, IStringLocalizer<BaseController> baseLocalizer, IHelper helper) : base(baseLocalizer, helper)
        {
            _eventsRepository = eventsRepository;
            _helper = helper;
        }

        #endregion


        [Route("{tenant}")]
        public ActionResult Index(string tenant)
        {
            lock (Lock)
            {
                var connectionString = _helper.GetBasicSqlConnectionString(Startup.DatabaseConfig);
                if (!string.IsNullOrEmpty(tenant))
                {
                    SetTenantConfig(tenant);

                    var events = _eventsRepository.GetEventsForTenant(connectionString, Startup.TenantConfig.TenantId);

                    return View(events);
                }

                return View("Error");

            }
        }
    }
}

