using System.Collections.Generic;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Core.Interfaces
{
    public interface ISectionRepository
    {
        List<SectionModel> GetSections(List<int> sectionIds, string connectionString, int tenantId);

        SectionModel GetSection(int sectionId, string connectionString, int tenantId);
    }
}
