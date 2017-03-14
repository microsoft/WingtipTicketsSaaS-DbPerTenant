using System.ComponentModel.DataAnnotations;

namespace Events_Tenant.Common.Models
{
    public class VenueModel
    {
        public string VenueName { get; set; }

        [EmailAddress(ErrorMessage = "Invalid Email Address")]
        public string AdminEmail { get; set; }

        [Display(Name = "Password")]
        [DataType(DataType.Password)]
        public string AdminPassword { get; set; }

        public string PostalCode { get; set; }

        public string CountryCode { get; set; }
    }
}
