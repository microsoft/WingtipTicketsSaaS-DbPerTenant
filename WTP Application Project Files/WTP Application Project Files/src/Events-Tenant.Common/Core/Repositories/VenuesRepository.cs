using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;
using Events_TenantUserApp.EF.Models;

namespace Events_Tenant.Common.Core.Repositories
{
    public class VenuesRepository : IVenuesRepository
    {
        public VenueModel GetVenueDetails(byte[] tenantId, DatabaseConfig databaseConfig, TenantServerConfig tenantServerConfig)
        {
            var connectionString = Helper.GetSqlConnectionString(databaseConfig);

            using (var context = new TenantEntities(Sharding.ShardMap, tenantId, connectionString, Helper.GetTenantConnectionString(databaseConfig, tenantServerConfig)))
            {
                var venueModel = context.Venues.FirstOrDefault();

                var venue = new VenueModel
                {
                    VenueName = venueModel.VenueName,
                    AdminEmail = venueModel.AdminEmail,
                    AdminPassword = venueModel.AdminPassword,
                    CountryCode = venueModel.CountryCode,
                    PostalCode = venueModel.PostalCode
                };

                return venue;
            }
        }
    }
}

