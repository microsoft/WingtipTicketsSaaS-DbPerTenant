using System;
using System.Collections.Generic;
using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;
using Events_TenantUserApp.Controllers;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Localization;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;
using Xunit;
using Assert = Xunit.Assert;

namespace Events_TenantUserApp.Tests.ControllerTests
{
    [TestClass]
    public class FindSeatsControllerTests
    {
        private readonly FindSeatsController _findSeatsController;

        public FindSeatsControllerTests(IStringLocalizer<FindSeatsController> localizer, IStringLocalizer<BaseController> baseLocalizer)
        {
            var mockEventsRepo = new Mock<IEventsRepository>();
            mockEventsRepo.Setup(repo => repo.GetEvent(1, "", 12345)).Returns(GetEventModel());

            var mockEventSectionRepo = new Mock<IEventSectionRepository>();
            mockEventSectionRepo.Setup(repo => repo.GetEventSections(1, "", 12345)).Returns(GetEventSections());

            var mockSectionRepo = new Mock<ISectionRepository>();
            var seatSectionIds = GetEventSections().Select(i => i.SectionId).ToList();
            mockSectionRepo.Setup(r => r.GetSections(seatSectionIds, "", 12345)).Returns(GetSeatSections());
            mockSectionRepo.Setup(r => r.GetSection(1, "", 12345)).Returns(GetSection());
                
            var mockTicketRepo = new Mock<ITicketRepository>();
            mockTicketRepo.Setup(r => r.GetTicketsSold(1, 1, "", 12345)).Returns(10);
            mockTicketRepo.Setup(r => r.Add(GetTicketModel(), "", 12345)).Returns(true);

            var mockTicketPurchaseRepo = new Mock<ITicketPurchaseRepository>();
            mockTicketPurchaseRepo.Setup(r => r.GetNumberOfTicketPurchases("", 12345)).Returns(10);
            mockTicketPurchaseRepo.Setup(r => r.Add(GetTicketPurchaseModel(), "", 12345)).Returns(11);

            var mockhelper = new Mock<IHelper>();
            mockhelper.Setup(helper => helper.GetBasicSqlConnectionString(new DatabaseConfig())).Returns("");

            _findSeatsController = new FindSeatsController(mockEventSectionRepo.Object, mockSectionRepo.Object, mockEventsRepo.Object, mockTicketRepo.Object, mockTicketPurchaseRepo.Object, mockhelper.Object, localizer, baseLocalizer);
        }

        [Fact]
        public void FindSeatsTests_EventId_Null()
        {
            var result = _findSeatsController.FindSeats("tenantName", 0);

            var redirectToActionResult = Assert.IsType<RedirectToActionResult>(result);
            Assert.NotNull(redirectToActionResult.ControllerName);
            Assert.Equal("Index", redirectToActionResult.ActionName);
            Assert.Equal("Events", redirectToActionResult.ControllerName);

        }

        [Fact]
        public void FindSeatsTests_EventId_NotNull()
        {
            var result = _findSeatsController.FindSeats("tenantName", 1);

            // Assert
            var viewResult = Assert.IsType<ViewResult>(result);
            var model = Assert.IsAssignableFrom<IEnumerable<EventModel>>(viewResult.Model);
            Assert.Equal(1, model.Count());
        }

        [Fact]
        public void GetAvailableSeatsTest()
        {
            var result = _findSeatsController.GetAvailableSeats("tenantName", 1, 1);

            // Assert
            var contentResult = Assert.IsType<ContentResult>(result);
            Assert.Equal("290", contentResult.Content);

        }

        [Fact]
        public void PurchaseTicketsTests()
        {
            var result = _findSeatsController.PurchaseTickets("tenantName", "1", "5", "100", "2", "1");

            var redirectToActionResult = Assert.IsType<RedirectToActionResult>(result);
            Assert.NotNull(redirectToActionResult.ControllerName);
            Assert.Equal("Index", redirectToActionResult.ActionName);
            Assert.Equal("Events", redirectToActionResult.ControllerName);

        }


        private EventModel GetEventModel()
        {
            return new EventModel
            {
                Date = DateTime.Now,
                EventId = 1,
                EventName = "String Serenades",
                SubTitle = "Contoso Chamber Orchestra"
            };
        }

        private List<EventSectionModel> GetEventSections()
        {
            return new List<EventSectionModel>
            {
                new EventSectionModel
                {
                    EventId = 1,
                    Price = 100,
                    SectionId = 1
                },
                new EventSectionModel
                {
                    EventId = 2,
                    Price = 1500,
                    SectionId = 1
                }
            };
        }

        private List<SectionModel> GetSeatSections()
        {
            return new List<SectionModel>
            {
                new SectionModel
                {
                    SeatRows = 10,
                    SectionId = 1,
                    SeatsPerRow = 30,
                    SectionName = "Main Auditorium Stage",
                    StandardPrice = 100
                },
                new SectionModel
                {
                    SeatRows = 10,
                    SectionId = 2,
                    SeatsPerRow = 30,
                    SectionName = "Main Auditorium Middle",
                    StandardPrice = 80
                }
            };
        }

        private SectionModel GetSection()
        {
            return new SectionModel
            {
                SeatRows = 10,
                SectionId = 1,
                SeatsPerRow = 30,
                SectionName = "Main Auditorium Stage",
                StandardPrice = 100
            };
        }

        private TicketPurchaseModel GetTicketPurchaseModel()
        {
            return new TicketPurchaseModel
            {
                CustomerId = 5,
                PurchaseTotal = 100
            };
        }

        private TicketModel GetTicketModel()
        {
            return new TicketModel
            {
                SectionId = 1,
                EventId = 1,
                RowNumber = 1000,
                SeatNumber = 1001
            };
        }
    }
}
