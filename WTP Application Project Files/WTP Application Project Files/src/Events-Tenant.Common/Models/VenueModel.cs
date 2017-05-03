using System.ComponentModel.DataAnnotations;

namespace Events_Tenant.Common.Models
{
    public class VenueModel
    {
        public string VenueName { get; set; }

        public string AdminEmail { get; set; }

        [DataType(DataType.Password)]
        public string AdminPassword { get; set; }

        public string PostalCode { get; set; }

        public string CountryCode { get; set; }

        public string VenueType { get; set; }
        public string DatabaseName { get; set; }
    }
}
