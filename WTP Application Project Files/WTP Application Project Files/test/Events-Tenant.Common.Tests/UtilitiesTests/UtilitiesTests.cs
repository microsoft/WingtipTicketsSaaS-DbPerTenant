using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Events_Tenant.Common.Interfaces;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;

namespace Events_Tenant.Common.Tests.UtilitiesTests
{
    [TestClass]
    public class UtilitiesTests
    {
        [TestMethod]
        public void GetUser()
        {
            var host = "events.wtp.bg1.trafficmanager.net";
            var hostpieces = host.Split(new[] { "." }, StringSplitOptions.RemoveEmptyEntries);
            var user = hostpieces[2];

            Assert.AreEqual("bg1", user);
        }

        [TestMethod]
        public void GetUser2()
        {
            var host = "localhost:41208";
            string[] hostpieces = host.Split(new[] { "." }, StringSplitOptions.RemoveEmptyEntries);
            var subdomain = hostpieces[0];
            Assert.AreEqual("localhost:41208", subdomain);
        }
    }
}
