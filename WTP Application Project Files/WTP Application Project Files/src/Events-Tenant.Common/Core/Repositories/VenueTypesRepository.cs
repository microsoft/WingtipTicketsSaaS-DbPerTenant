using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Core.Repositories
{
    public class VenueTypesRepository : BaseRepository, IVenueTypesRepository
    {
        public VenueTypeModel GetVenueType(string venueType, string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                var venueTypesDetails = context.VenueTypes.Where(i => i.VenueType == venueType);

                if (venueTypesDetails.Any())
                {
                    var venueTypeDetails = venueTypesDetails.FirstOrDefault();
                    return new VenueTypeModel
                    {
                        VenueType = venueTypeDetails.VenueType.Trim(),
                        EventTypeName = venueTypeDetails.EventTypeName.Trim(),
                        EventTypeShortName = venueTypeDetails.EventTypeShortName.Trim(),
                        EventTypeShortNamePlural = venueTypeDetails.EventTypeShortNamePlural.Trim(),
                        Language = venueTypeDetails.Language.Trim(),
                        VenueTypeName = venueTypeDetails.VenueTypeName.Trim()
                    };
                }
            }
            return null;
        }
    }
}
