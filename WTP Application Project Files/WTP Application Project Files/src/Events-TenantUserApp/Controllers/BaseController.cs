using System.Globalization;
using System.Threading;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Localization;

namespace Events_TenantUserApp.Controllers
{
    public class BaseController : Controller
    {
        #region Fields
        private readonly IStringLocalizer<BaseController> _localizer;
        #endregion


        #region Constructors
        public BaseController(IStringLocalizer<BaseController> localizer) 
        {
            _localizer = localizer;
            Thread.CurrentThread.CurrentCulture = CultureInfo.CreateSpecificCulture(Startup.TenantConfig.TenantCulture);
            Thread.CurrentThread.CurrentUICulture = new CultureInfo(Startup.TenantConfig.TenantCulture);
        }

        #endregion


        #region Overidden Methods

        //protected override void Initialize(RequestContext requestContext)
        //{
        //    base.Initialize(requestContext);
        //    ExtractHostingSite();
        //}

        #endregion

        #region Protected Methods

        protected void DisplayMessage(string content)
        {
            if (!string.IsNullOrWhiteSpace(content))
            {
                var confirmationMsg = _localizer["Confirmation"];

                TempData["msg"] = $"<script>showAlert(\'{confirmationMsg}\', '{content}');</script>";
            }
        }

        #endregion

        #region Private Methods

        //private void ExtractHostingSite()
        //{
        //    var requestUrl = Request.Url;

        //    if (requestUrl == null)
        //    {
        //        throw new Exception("No request Url to resolve the Host");
        //    }

        //    if (!requestUrl.Host.Contains("trafficmanager.net"))
        //    {
        //        ViewBag.SiteHostName = requestUrl.Host;
        //    }
        //    else
        //    {
        //        try
        //        {
        //            var resolvedHostName = Dns.GetHostEntry(requestUrl.Host);

        //            if (resolvedHostName.HostName.Contains("waws"))
        //            {
        //                ViewBag.SiteHostName = Environment.ExpandEnvironmentVariables("%WEBSITE_SITE_NAME%") +
        //                                       ".azurewebsites.net";
        //            }
        //            else
        //            {
        //                ViewBag.SiteHostName = resolvedHostName.HostName;
        //            }
        //        }
        //        catch
        //        {
        //            throw new Exception(String.Format("Unable to resolve host for {0}", requestUrl.Host));
        //        }
        //    }
        //}

        #endregion
    }
}
