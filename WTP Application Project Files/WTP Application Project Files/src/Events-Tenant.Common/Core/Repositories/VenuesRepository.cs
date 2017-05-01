using System.Data.SqlClient;
using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;

namespace Events_Tenant.Common.Core.Repositories
{
    public class VenuesRepository : BaseRepository, IVenuesRepository
    {
        public VenueModel GetVenueDetails(string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                //get database name
                string databaseName;
                using (SqlConnection sqlConn = Sharding.ShardMap.OpenConnectionForKey(tenantId, connectionString))
                {
                    databaseName = sqlConn.Database;
                }

                var venueModel = context.Venue.FirstOrDefault();

                var venue = new VenueModel
                {
                    VenueName = venueModel.VenueName.Trim(),
                    AdminEmail = venueModel.AdminEmail.Trim(),
                    AdminPassword = venueModel.AdminPassword,
                    CountryCode = venueModel.CountryCode.Trim(),
                    PostalCode = venueModel.PostalCode,
                    VenueType = venueModel.VenueType.Trim(),
                    DatabaseName = databaseName
                };
                return venue;
            }
        }
    }
}

