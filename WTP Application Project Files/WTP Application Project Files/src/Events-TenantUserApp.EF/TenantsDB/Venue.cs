namespace Events_TenantUserApp.EF.TenantsDB
{
    public partial class Venue
    {
        public string VenueName { get; set; }
        public string VenueType { get; set; }
        public string AdminEmail { get; set; }
        public string AdminPassword { get; set; }
        public string PostalCode { get; set; }
        public string CountryCode { get; set; }
        public string Lock { get; set; }

        public virtual Countries CountryCodeNavigation { get; set; }
        public virtual VenueTypes VenueTypeNavigation { get; set; }
    }
}
