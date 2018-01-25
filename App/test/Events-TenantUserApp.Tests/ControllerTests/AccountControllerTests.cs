using System.Threading.Tasks;
using Events_Tenant.Common.Interfaces;
using Events_Tenant.Common.Models;
using Events_TenantUserApp.Controllers;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Localization;
using Microsoft.Extensions.Logging;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;
using Xunit;
using Assert = Xunit.Assert;

namespace Events_TenantUserApp.Tests.ControllerTests
{
    [TestClass]
    public class AccountControllerTests
    {
        private readonly AccountController _accountController;

        public AccountControllerTests(IStringLocalizer<AccountController> localizer, IStringLocalizer<BaseController> baseLocalizer, ILogger<AccountController> logger, IConfiguration configuration)
        {
            var mockTenantRepo = new Mock<ITenantRepository>();
            mockTenantRepo.Setup(repo => repo.GetCustomer("test@email.com", 123456)).Returns(GetCustomerAsync());
            mockTenantRepo.Setup(repo => repo.AddCustomer(GetCustomer(), 123456)).Returns(GetCustomerId());

            var mockCatalogRepo = new Mock<ICatalogRepository>();

            var mockUtilities = new Mock<IUtilities>();

            _accountController = new AccountController(localizer, baseLocalizer, mockTenantRepo.Object, mockCatalogRepo.Object, logger, configuration);

        }

        [Fact]
        public void LoginTest()
        {
            //Act
            var result = _accountController.Login("tenantName", "test@email.com");

            // Assert
            var redirectToActionResult = Assert.IsType<RedirectToActionResult>(result);
            Assert.Null(redirectToActionResult.ControllerName);
        }

        [Fact]
        public void LogoutTest()
        {
            //Act
            var result = _accountController.Logout("tenantName", "testemail@gmail.com");

            // Assert
            var redirectToActionResult = Assert.IsType<RedirectToActionResult>(result);
            Assert.NotNull(redirectToActionResult.ControllerName);
            Assert.Equal("Index", redirectToActionResult.ActionName);
            Assert.Equal("Events", redirectToActionResult.ControllerName);
        }

        [Fact]
        public void RegisterCustomerTest()
        {
            //Act
            var result = _accountController.Register("tenantName", GetCustomer());

            // Assert
            var redirectToActionResult = Assert.IsType<RedirectToActionResult>(result);
            Assert.Null(redirectToActionResult.ControllerName);
        }

        private CustomerModel GetCustomer()
        {
            return new CustomerModel
            {
                CountryCode = "USA",
                PostalCode = "123",
                Email = "test@gmail.com",
                FirstName = "customer1",
                LastName = "lastName"
            };
        }

        private async Task<int> GetCustomerId()
        {
            return 1;
        }
        private async Task<CustomerModel> GetCustomerAsync()
        {
            return new CustomerModel
            {
                CountryCode = "USA",
                PostalCode = "123",
                Email = "test@gmail.com",
                FirstName = "customer1",
                LastName = "lastName"
            };
        }

    }
}
