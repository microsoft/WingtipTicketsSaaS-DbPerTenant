using System.Collections.Generic;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Tests.MockRepositories;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Events_Tenant.Common.Tests.RepositoriesTests
{
    [TestClass]
    public class SectionRepositoryTests
    {
        private ISectionRepository _sectionRepository;
        private string _connectionString;
        private int _tenantId;


        [TestInitialize]
        public void Setup()
        {
            _sectionRepository = new MockSectionRepository();
            _connectionString = "User ID=developer;Password=password;Connect Timeout=0;Application Name=EntityFramework";
            _tenantId = 1368421345;
        }


        [TestMethod]
        public void GetSectionsTest()
        {
            List<int> sectionIds = new List<int> {1,2};

            var result = _sectionRepository.GetSections(sectionIds, _connectionString, _tenantId);
            Assert.IsNotNull(result);
            Assert.AreEqual(2, result.Count);
            Assert.AreEqual(1, result[0].SectionId);
            Assert.AreEqual(10, result[0].SeatsPerRow);
            Assert.AreEqual("section 1", result[0].SectionName);
            Assert.AreEqual(100, result[0].StandardPrice);
            Assert.AreEqual(4, result[0].SeatRows);

            Assert.AreEqual(2, result[1].SectionId);
            Assert.AreEqual(20, result[1].SeatsPerRow);
            Assert.AreEqual("section 2", result[1].SectionName);
            Assert.AreEqual(80, result[1].StandardPrice);
            Assert.AreEqual(5, result[1].SeatRows);

        }

        [TestMethod]
        public void GetSectionTest()
        {
           var result = _sectionRepository.GetSection(1, _connectionString, _tenantId);
            Assert.IsNotNull(result);
            Assert.AreEqual(1, result.SectionId);
            Assert.AreEqual(10, result.SeatsPerRow);
            Assert.AreEqual("section 1", result.SectionName);
            Assert.AreEqual(100, result.StandardPrice);
            Assert.AreEqual(4, result.SeatRows);
        }
    }
}
