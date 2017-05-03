using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;
using Events_TenantUserApp.Controllers;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Localization;
using Moq;
using Xunit;


namespace Events_TenantUserApp.UnitTests.ControllerTests
{
   // [TestClass]
    public class HomeControllerTests
    {
        //Controllers tests are being done here because the core cannot be referenced in the unit tests projects
        //https://docs.microsoft.com/en-us/aspnet/core/mvc/controllers/testing
        //https://github.com/aspnet/Tooling/issues/664
        //http://stackoverflow.com/questions/40190679/how-to-reference-an-asp-net-core-project-from-a-full-net-framework-test-project


        private HomeController _homeController;



        [Fact]
        public void Index_GetTenantDetails()
        {
            // Arrange
            var mockTenantRepo = new Mock<ITenantsRepository>();
            var mockVenuesRepo = new Mock<IVenuesRepository>();
            var mockhelper = new Mock<IHelper>();

            mockTenantRepo.Setup(repo => repo.GetAllTenants()).Returns(GetTenants());

            _homeController = new HomeController(mockTenantRepo.Object, mockVenuesRepo.Object, mockhelper.Object);

            //Act
            var result = _homeController.Index();

            // Assert
            var redirectToActionResult = Assert.IsType<RedirectToActionResult>(result);
            Assert.Null(redirectToActionResult.ControllerName);
            Assert.Equal("Index", redirectToActionResult.ActionName);



            //var badRequestResult = Assert.IsType<BadRequestObjectResult>(result);
            //Assert.IsType<SerializableError>(badRequestResult.Value);
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
