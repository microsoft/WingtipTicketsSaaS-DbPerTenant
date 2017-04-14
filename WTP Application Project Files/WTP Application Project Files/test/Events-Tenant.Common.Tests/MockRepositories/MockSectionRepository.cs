using System.Collections.Generic;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Tests.MockRepositories
{
    public class MockSectionRepository : ISectionRepository
    {
        public List<SectionModel> SectionModels { get; set; }

        public MockSectionRepository()
        {
            SectionModels = new List<SectionModel>
            {
                new SectionModel
                {
                    SectionId = 1,
                    SeatsPerRow = 10,
                    SectionName = "section 1",
                    StandardPrice = 100,
                    SeatRows = 4
                },
                new SectionModel
                {
                    SectionId = 2,
                    SeatsPerRow = 20,
                    SectionName = "section 2",
                    StandardPrice = 80,
                    SeatRows = 5
                }
            };
        }

        public List<SectionModel> GetSections(List<int> sectionIds, string connectionString, int tenantId)
        {
            return SectionModels;
        }

        public SectionModel GetSection(int sectionId, string connectionString, int tenantId)
        {
            return SectionModels[0];
        }
    }
}