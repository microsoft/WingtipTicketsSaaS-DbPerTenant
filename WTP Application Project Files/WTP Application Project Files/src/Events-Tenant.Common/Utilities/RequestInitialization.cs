
namespace Events_Tenant.Common.Utilities
{
    public class RequestInitialization
    {
        #region - Fields -

        //private static VenuesRepository _venuesRepository;
        //private static VenueTypesRepository _venueTypesRepository;
       // private static IHttpContextAccessor _httpContextAccessor;

        #endregion

        //public RequestInitialization(IHttpContextAccessor httpContextAccessor)
        //{
        //    _httpContextAccessor = httpContextAccessor;
        //}

        public  void InitializeTenantConfig()
        {
            //get venuename from url

           //string venueName = _httpContextAccessor.HttpContext.Request.PathBase;

           // if (!string.IsNullOrEmpty(venueName) && venueName.Length > 1)
           // {
           //     // Retrieve the tenant configuration details from the tenant's database
           //     var venue = venueName.Substring(1, venueName.Length - 2);
           //     //PopulateTenantConfig(venue);


           //     //// tenant configuration is placed in the context so it is available throughout the request
           //     //HttpContext.Current.Items.Add("TenantInfo", _tenantConfig);
           // }
        }

    }
}
