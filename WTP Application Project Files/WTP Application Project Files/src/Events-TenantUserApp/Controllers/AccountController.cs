using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Security.Claims;
using System.Threading;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Localization;

namespace Events_TenantUserApp.Controllers
{
    public class AccountController : BaseController
    {
        #region Fields

        private readonly ICustomerRepository _customerRepository;
        private readonly IStringLocalizer<AccountController> _localizer;
        private readonly IHelper _helper;
        private readonly string _connectionString;

        #endregion


        #region Constructors

        public AccountController(IStringLocalizer<AccountController> localizer, IStringLocalizer<BaseController> baseLocalizer, ICustomerRepository customerRepository, IHelper helper)
            : base(baseLocalizer)
        {
            _localizer = localizer;
            _customerRepository = customerRepository;
            _helper = helper;

            Thread.CurrentThread.CurrentCulture = CultureInfo.CreateSpecificCulture(Startup.TenantConfig.TenantCulture);
            Thread.CurrentThread.CurrentUICulture = new CultureInfo(Startup.TenantConfig.TenantCulture);

            _connectionString = _helper.GetSqlConnectionString(Startup.DatabaseConfig);

        }

        #endregion


        [HttpPost]
        public ActionResult Login(string email)
        {
            if (string.IsNullOrWhiteSpace(email))
            {
                var message = _localizer["Please type your email."];
                DisplayMessage(message);
            }
            else
            {
                var customer = _customerRepository.GetCustomer(email, _connectionString, Startup.TenantConfig.TenantId);
                if (customer != null)
                {
                    HttpContext.Session.SetObjectAsJson("SessionUser", customer);
                    if (Startup.SessionUsers.Any(a => a.Email != null && a.Email.ToUpper() == email.ToUpper()))
                    {
                        Startup.SessionUsers.Remove(Startup.SessionUsers.First(a => a.Email.ToUpper() == email.ToUpper()));
                    }

                    Startup.SessionUsers.Add(customer);

                    var userClaims = new List<Claim>
                    {
                        new Claim(ClaimTypes.Email, customer.Email)
                    };

                    var principal = new ClaimsPrincipal(new ClaimsIdentity(userClaims, "SessionUser"));
                    HttpContext.Authentication.SignInAsync("MyCookieMiddlewareInstance", principal);
                }
                else
                {
                    var message = _localizer["The user does not exist."];
                    DisplayMessage(message);
                }
            }

            return Redirect(Request.Headers["Referer"].ToString());
        }

        public ActionResult Logout()
        {
            if (User.Identity.IsAuthenticated)
            {
                Startup.SessionUsers = new List<CustomerModel>();
                HttpContext.Session.Clear();

                HttpContext.Authentication.SignOutAsync("MyCookieMiddlewareInstance");
            }

            return RedirectToAction("Index", "Events", new {tenant = Startup.TenantConfig.TenantName});
        }

        [HttpPost]
        public ActionResult Register(CustomerModel customerModel)
        {
            if (!ModelState.IsValid)
            {
                return RedirectToAction("Index", "Events", new {tenant = Startup.TenantConfig.TenantName});
            }

            if (Startup.SessionUsers.Any(a => a.Email == customerModel.Email))
            {
                var message = _localizer["User already exists in session."];
                DisplayMessage(message);
            }

            //check if customer already exists
            var customer = _customerRepository.GetCustomer(customerModel.Email, _connectionString, Startup.TenantConfig.TenantId);

            if (customer == null)
            {
                var customerId = _customerRepository.Add(customerModel, _connectionString, Startup.TenantConfig.TenantId);
                customerModel.CustomerId = customerId;
                HttpContext.Session.SetObjectAsJson("SessionUser", customerModel);
                Startup.SessionUsers.Add(customerModel);

                var userClaims = new List<Claim>
                {
                    new Claim(ClaimTypes.Email, customerModel.Email)
                };

                var principal = new ClaimsPrincipal(new ClaimsIdentity(userClaims, "SessionUser"));
                HttpContext.Authentication.SignInAsync("MyCookieMiddlewareInstance", principal);
            }
            else
            {
                var message = _localizer["User already exists."];
                DisplayMessage(message);
            }
            return Redirect(Request.Headers["Referer"].ToString());
        }
    }
}
