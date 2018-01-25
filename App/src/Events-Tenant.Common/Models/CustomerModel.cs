using System.ComponentModel.DataAnnotations;

namespace Events_Tenant.Common.Models
{
    public class CustomerModel
    {
        public int CustomerId { get; set; }

        [Required]
        public string FirstName { get; set; }

        [Required]
        public string LastName { get; set; }

        [Required]
        public string Email { get; set; }

        [DataType(DataType.Password)]
        public string Password { get; set; }

        public string PostalCode { get; set; }

        public string CountryCode { get; set; }

        public string TenantName { get; set; }
    }
}
