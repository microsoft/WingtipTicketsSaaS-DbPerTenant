using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;
using Events_TenantUserApp.EF.Models;

namespace Events_Tenant.Common.Core.Repositories
{
    public class VenueTypesRepository : IVenueTypesRepository
    {
        public VenueTypeModel GetVenueType(string venueType, byte[] tenantId, DatabaseConfig databaseConfig, TenantServerConfig tenantServerConfig)
        {
            var connectionString = Helper.GetSqlConnectionString(databaseConfig);

            using (var context = new TenantEntities(Sharding.ShardMap, tenantId, connectionString, Helper.GetTenantConnectionString(databaseConfig, tenantServerConfig)))
            {
                var venueTypeDetails = context.VenueTypes.First(i => i.VenueType == venueType);

                var venueTypeModel = new VenueTypeModel
                {
                    VenueType = venueTypeDetails.VenueType,
                    EventTypeName = venueTypeDetails.EventTypeName,
                    EventTypeShortName = venueTypeDetails.EventTypeShortName,
                    EventTypeShortNamePlural = venueTypeDetails.EventTypeShortNamePlural,
                    Language = venueTypeDetails.Language,
                    VenueTypeName = venueTypeDetails.VenueTypeName
                };

                return venueTypeModel;
            }
        }
    }
}
