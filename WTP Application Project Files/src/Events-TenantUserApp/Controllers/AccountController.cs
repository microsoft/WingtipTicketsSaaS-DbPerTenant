using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Events_Tenant.Common.Interfaces;
using Events_Tenant.Common.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Localization;
using Microsoft.Extensions.Logging;

namespace Events_TenantUserApp.Controllers
{
    [Route("{tenant}/Account")]
    public class AccountController : BaseController
    {
        #region Fields

        private readonly ITenantRepository _tenantRepository;
        private readonly IStringLocalizer<AccountController> _localizer;
        private readonly ICatalogRepository _catalogRepository;
        private readonly ILogger _logger;
        private readonly DnsClient.ILookupClient _client;

        #endregion

        #region Constructors

        public AccountController(IStringLocalizer<AccountController> localizer, IStringLocalizer<BaseController> baseLocalizer, ITenantRepository tenantRepository, ICatalogRepository catalogRepository, ILogger<AccountController> logger, IConfiguration configuration, DnsClient.ILookupClient client)
            : base(baseLocalizer, tenantRepository, configuration, client)
        {
            _localizer = localizer;
            _tenantRepository = tenantRepository;
            _catalogRepository = catalogRepository;
            _logger = logger;
            _client = client;
        }

        #endregion

        [HttpPost]
        [Route("Login")]
        public async Task<ActionResult> Login(string tenant, string regEmail)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(regEmail))
                {
                    var message = _localizer["Please type your email."];
                    DisplayMessage(message, "Error");
                }
                else
                {
                    var tenantDetails = (_catalogRepository.GetTenant(tenant)).Result;

                    if (tenantDetails != null)
                    {
                        SetTenantConfig(tenantDetails.TenantId, tenantDetails.TenantIdInString);

                        var customer = await _tenantRepository.GetCustomer(regEmail, tenantDetails.TenantId);

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
                    else
                    {
                        return View("TenantError", tenant);
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(0, ex, "Login failed for tenant {tenant}", tenant);
                return View("TenantError", tenant);
            }
            return Redirect(Request.Headers["Referer"].ToString());
        }

        [Route("Logout")]
        public ActionResult Logout(string tenant, string email)
        {
            try
            {
                var userSessions = HttpContext.Session.GetObjectFromJson<List<CustomerModel>>("SessionUsers");
                if (userSessions != null)
                {
                    userSessions.Remove(userSessions.First(a => a.Email.ToUpper() == email.ToUpper() && a.TenantName == tenant));
                    HttpContext.Session.SetObjectAsJson("SessionUsers", userSessions);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(0, ex, "Log out failed for tenant {tenant}", tenant);
                return View("TenantError", tenant);
            }
            return RedirectToAction("Index", "Events", new { tenant });
        }

        [HttpPost]
        [Route("Register")]
        public async Task<ActionResult> Register(string tenant, CustomerModel customerModel)
        {
            try
            {
                if (!ModelState.IsValid)
                {
                    return RedirectToAction("Index", "Events", new { tenant });
                }

                var tenantDetails = (_catalogRepository.GetTenant(tenant)).Result;
                if (tenantDetails != null)
                {
                    SetTenantConfig(tenantDetails.TenantId, tenantDetails.TenantIdInString);

                    //check if customer already exists
                    var customer = (_tenantRepository.GetCustomer(customerModel.Email, tenantDetails.TenantId)).Result;

                    if (customer == null)
                    {
                        var customerId = await _tenantRepository.AddCustomer(customerModel, tenantDetails.TenantId);
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
                }
                else
                {
                    return View("TenantError", tenant);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(0, ex, "Registration failed for tenant {tenant}", tenant);
                return View("TenantError", tenant);
            }
            return Redirect(Request.Headers["Referer"].ToString());
        }
    }
}
