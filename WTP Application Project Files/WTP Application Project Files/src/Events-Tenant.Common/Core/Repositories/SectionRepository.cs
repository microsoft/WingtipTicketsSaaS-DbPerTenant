using System.Collections.Generic;
using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Core.Repositories
{
    public class SectionRepository : BaseRepository, ISectionRepository
    {
        public List<SectionModel> GetSections(List<int> sectionIds, string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                var sections = context.Sections.Where(i => sectionIds.Contains(i.SectionId));

                if (sections.Any())
                {
                    List<SectionModel> sectionModelList = new List<SectionModel>();
                    foreach (var section in sections)
                    {
                        var sectionModel = new SectionModel
                        {
                            SectionId = section.SectionId,
                            SeatsPerRow = section.SeatsPerRow,
                            SectionName = section.SectionName,
                            SeatRows = section.SeatRows,
                            StandardPrice = section.StandardPrice
                        };

                        sectionModelList.Add(sectionModel);
                    }

                    return sectionModelList;
                }
            }
            return null;
        }

        public SectionModel GetSection(int sectionId, string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                var sections = context.Sections.Where(i => i.SectionId == sectionId);

                if (sections.Any())
                {
                    var section = sections.FirstOrDefault();

                    return new SectionModel
                    {
                        SectionId = section.SectionId,
                        SeatsPerRow = section.SeatsPerRow,
                        SeatRows = section.SeatRows,
                        StandardPrice = section.StandardPrice,
                        SectionName = section.SectionName
                    };
                }
            }
            return null;
        }
    }
}
