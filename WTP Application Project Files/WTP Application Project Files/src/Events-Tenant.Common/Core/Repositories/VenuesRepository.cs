using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Core.Repositories
{
    public class VenuesRepository : BaseRepository, IVenuesRepository
    {
        public VenueModel GetVenueDetails(string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                var venueModel = context.Venue.FirstOrDefault();

                var venue = new VenueModel
                {
                    VenueName = venueModel.VenueName.Trim(),
                    AdminEmail = venueModel.AdminEmail.Trim(),
                    AdminPassword = venueModel.AdminPassword,
                    CountryCode = venueModel.CountryCode.Trim(),
                    PostalCode = venueModel.PostalCode.Trim(),
                    VenueType = venueModel.VenueType.Trim()
                };
                return venue;
            }
        }
    }
}

