using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Models;
using Events_TenantUserApp.Controllers;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Localization;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;
using Xunit;
using Assert = Xunit.Assert;

namespace Events_TenantUserApp.Tests.ControllerTests
{
    [TestClass]
    public class AccountControllerTests
    {
        private AccountController _accountController;

        public AccountControllerTests(IStringLocalizer<AccountController> localizer, IStringLocalizer<BaseController> baseLocalizer)
        {
            var mockCustomerRepo = new Mock<ICustomerRepository>();
            mockCustomerRepo.Setup(repo => repo.GetCustomer("test@email.com", "", 123456)).Returns(GetCustomer());
            mockCustomerRepo.Setup(repo => repo.Add(GetCustomer(), "", 123456)).Returns(1);

            var mockhelper = new Mock<IHelper>();

            _accountController = new AccountController(localizer, baseLocalizer, mockCustomerRepo.Object, mockhelper.Object);

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

        private CustomerModel GetNullCustomer()
        {
            return null;
        }
    }
}
