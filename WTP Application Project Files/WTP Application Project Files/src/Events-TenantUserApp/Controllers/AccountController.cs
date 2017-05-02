using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Security.Claims;
using System.Threading;
using System.Threading.Tasks;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Localization;

namespace Events_TenantUserApp.Controllers
{
    [Route("{tenant}/Account")]
    public class AccountController : BaseController
    {
        #region Fields

        private readonly ICustomerRepository _customerRepository;
        private readonly IStringLocalizer<AccountController> _localizer;
        private readonly string _connectionString;

        #endregion

        #region Constructors

        public AccountController(IStringLocalizer<AccountController> localizer, IStringLocalizer<BaseController> baseLocalizer, ICustomerRepository customerRepository, IHelper helper)
            : base(baseLocalizer, helper)
        {
            _localizer = localizer;
            _customerRepository = customerRepository;

            Thread.CurrentThread.CurrentCulture = CultureInfo.CreateSpecificCulture(Startup.TenantConfig.TenantCulture);
            Thread.CurrentThread.CurrentUICulture = new CultureInfo(Startup.TenantConfig.TenantCulture);

            _connectionString = helper.GetBasicSqlConnectionString(Startup.DatabaseConfig);

        }

        #endregion

        [HttpPost]
        [Route("Login")]
        public ActionResult Login(string tenant, string regEmail)
        {
            if (string.IsNullOrWhiteSpace(regEmail))
            {
                var message = _localizer["Please type your email."];
                DisplayMessage(message , "Error");
            }
            else
            {
                SetTenantConfig(tenant);

                var customer = _customerRepository.GetCustomer(regEmail, _connectionString, Startup.TenantConfig.TenantId);
                if (customer != null)
                {
                    customer.TenantName = tenant;

                    var userSessions = HttpContext.Session.GetObjectFromJson<List<CustomerModel>>("SessionUsers");
                    if (userSessions == null)
                    {
                        userSessions = new List<CustomerModel>
                        {
                            customer
                        };
                        HttpContext.Session.SetObjectAsJson("SessionUsers", userSessions);
                    }
                    else
                    {
                        userSessions.Add(customer);
                        HttpContext.Session.SetObjectAsJson("SessionUsers", userSessions);
                    }
                }
                else
                {
                    var message = _localizer["The user does not exist."];
                    DisplayMessage(message, "Error");
                }
            }

            return Redirect(Request.Headers["Referer"].ToString());
        }

        [Route("Logout")]
        public ActionResult Logout(string tenant, string email)
        {
            SetTenantConfig(tenant);

            var userSessions = HttpContext.Session.GetObjectFromJson<List<CustomerModel>>("SessionUsers");
            if (userSessions!= null)
            {
                userSessions.Remove(userSessions.First(a => a.Email.ToUpper() == email.ToUpper() && a.TenantName == tenant));
                HttpContext.Session.SetObjectAsJson("SessionUsers", userSessions);
            }

            return RedirectToAction("Index", "Events", new {tenant = Startup.TenantConfig.TenantName});
        }

        [HttpPost]
        [Route("Register")]
        public ActionResult Register(string tenant, CustomerModel customerModel)
        {
            if (!ModelState.IsValid)
            {
                return RedirectToAction("Index", "Events", new {tenant = Startup.TenantConfig.TenantName});
            }

            SetTenantConfig(tenant);

            //check if customer already exists
            var customer = _customerRepository.GetCustomer(customerModel.Email, _connectionString, Startup.TenantConfig.TenantId);

            if (customer == null)
            {
                var customerId = _customerRepository.Add(customerModel, _connectionString, Startup.TenantConfig.TenantId);
                customerModel.CustomerId = customerId;
                customerModel.TenantName = tenant;

                var userSessions = HttpContext.Session.GetObjectFromJson<List<CustomerModel>>("SessionUsers");
                if (userSessions == null)
                {
                    userSessions = new List<CustomerModel>
                    {
                        customerModel
                    };
                    HttpContext.Session.SetObjectAsJson("SessionUsers", userSessions);
                }
                else
                {
                    userSessions.Add(customerModel);
                    HttpContext.Session.SetObjectAsJson("SessionUsers", userSessions);
                }
            }
            else
            {
                var message = _localizer["User already exists."];
                DisplayMessage(message, "Error");
            }
            return Redirect(Request.Headers["Referer"].ToString());
        }
    }
}
