using System.Collections.Generic;
using System.Globalization;
using System.Threading;
using Events_Tenant.Common.Utilities;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Localization;
using System.Linq;
using Events_Tenant.Common.Helpers;

namespace Events_TenantUserApp.Controllers
{
    public class BaseController : Controller
    {
        #region Fields
        private readonly IStringLocalizer<BaseController> _localizer;
        private readonly IMemoryCache _memoryCache;
        private readonly IHelper _helper;
        #endregion

        #region Constructors
        public BaseController(IStringLocalizer<BaseController> localizer, IMemoryCache memoryCache, IHelper helper) 
        {
            _localizer = localizer;
            _memoryCache = memoryCache;
            _helper = helper;

            Thread.CurrentThread.CurrentCulture = CultureInfo.CreateSpecificCulture(Startup.TenantConfig.TenantCulture);
            Thread.CurrentThread.CurrentUICulture = new CultureInfo(Startup.TenantConfig.TenantCulture);
        }

        #endregion

        #region Protected Methods

        protected void DisplayMessage(string content, string header)
        {
            if (!string.IsNullOrWhiteSpace(content))
            {
                string heading = header == "Confirmation" ? _localizer["Confirmation"] : _localizer["Error"];

                TempData["msg"] = $"<script>showAlert(\'{heading}\', '{content}');</script>";
            }
        }

        protected void SetTenantConfig(string tenant)
        {
            var tenantConfigs = new List<TenantConfig>();
            _memoryCache.TryGetValue("TenantConfigs", out tenantConfigs);

            if (tenantConfigs == null)
            {
                var fullAddress = HttpContext.Request.Headers["Referer"].ToString();
                Startup.TenantConfig = _helper.PopulateTenantConfigs(tenant, fullAddress,
                    Startup.DatabaseConfig, Startup.TenantConfig);
                tenantConfigs = new List<TenantConfig> { Startup.TenantConfig };

                _memoryCache.Set("TenantConfigs", tenantConfigs);
            }
            else
            {
                var tenantsInfo = tenantConfigs.Where(i => i.TenantName == tenant);

                if (!tenantsInfo.Any())
                {
                    var fullAddress = HttpContext.Request.Headers["Referer"].ToString();
                    Startup.TenantConfig = _helper.PopulateTenantConfigs(tenant, fullAddress, Startup.DatabaseConfig, Startup.TenantConfig);
                    tenantConfigs.Add(Startup.TenantConfig);

                    _memoryCache.Set("TenantConfigs", tenantConfigs);
                }
                else
                {
                    Startup.TenantConfig = tenantsInfo.First();
                }
            }

            //localisation per venue's language
            var culture = Startup.TenantConfig.TenantCulture;
            if (!string.IsNullOrEmpty(culture))
            {
                Thread.CurrentThread.CurrentCulture = CultureInfo.CreateSpecificCulture(culture);
                Thread.CurrentThread.CurrentUICulture = new CultureInfo(culture);
            }
        }
        #endregion

    }
}
