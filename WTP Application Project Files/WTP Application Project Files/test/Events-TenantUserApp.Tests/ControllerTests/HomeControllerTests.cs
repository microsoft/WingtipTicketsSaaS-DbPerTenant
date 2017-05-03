using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Models;
using Events_TenantUserApp.Controllers;
using Microsoft.AspNetCore.Mvc;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;
using Xunit;
using Assert = Xunit.Assert;

namespace Events_TenantUserApp.Tests.ControllerTests
{
    //https://docs.microsoft.com/en-us/aspnet/core/mvc/controllers/testing
    //https://docs.microsoft.com/en-us/dotnet/articles/core/testing/unit-testing-with-dotnet-test
    //https://github.com/aspnet/Tooling/issues/664
    //http://stackoverflow.com/questions/40190679/how-to-reference-an-asp-net-core-project-from-a-full-net-framework-test-project


    [TestClass]
    public class HomeControllerTests
    {
        private readonly HomeController _homeController;

        public HomeControllerTests()
        {
            // Arrange
            var mockTenantRepo = new Mock<ITenantsRepository>();
            var mockVenuesRepo = new Mock<IVenuesRepository>();

            var mockhelper = new Mock<IHelper>();

            mockTenantRepo.Setup(repo => repo.GetAllTenants()).Returns(GetTenants());
            mockVenuesRepo.Setup(repo => repo.GetVenueDetails("", 1234646)).Returns(GetVenueDetails());

            _homeController = new HomeController(mockTenantRepo.Object, mockVenuesRepo.Object, mockhelper.Object);
        }


        [Fact]
        public void Index_GetAllTenantDetails()
        {
            //Act
            var result = _homeController.Index();

            // Assert
            var redirectToActionResult = Assert.IsType<RedirectToActionResult>(result);
            Assert.NotNull(redirectToActionResult.ControllerName);
            Assert.Equal("Index", redirectToActionResult.ActionName);
        }

        private VenueModel GetVenueDetails()
        {
            return new VenueModel
            {
                AdminEmail = "adminEmail",
                AdminPassword = "Password",
                CountryCode = "USA",
                PostalCode = "123",
                VenueName = "Venue Name",
                VenueType = "classic"
            };
        }

        private List<TenantModel> GetTenants()
        {
            return new List<TenantModel>
            {
                new TenantModel
                {
                    TenantName = "dogwooddojo",
                    VenueName = "Dogwood Dojo",
                    ServicePlan = "Standard"
                },
                new TenantModel
                {
                    TenantName = "contosoconcerthall",
                    VenueName = "Contoso Concert Hall",
                    ServicePlan = "Standard"
                },
                new TenantModel
                {
                    TenantName = "fabrikamjazzclub",
                    VenueName = "Fabrikam Jazz Club",
                    ServicePlan = "Standard"
                }
            };
        }
    }
}
