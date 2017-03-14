using System.ComponentModel.DataAnnotations;

namespace Events_Tenant.Common.Models
{
    public class CustomerModel
    {
        public int CustomerId { get; set; }

        public string FirstName { get; set; }

        public string LastName { get; set; }

        [EmailAddress(ErrorMessage = "Invalid Email Address")]
        public string Email { get; set; }

        [Display(Name = "Password")]
        [DataType(DataType.Password)]
        public string Password { get; set; }

        public string PostalCode { get; set; }

        public string CountryCode { get; set; }
    }
}
