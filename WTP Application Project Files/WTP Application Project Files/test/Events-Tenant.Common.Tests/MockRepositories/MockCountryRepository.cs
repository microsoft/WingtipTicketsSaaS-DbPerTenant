using System.Collections.Generic;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Tests.MockRepositories
{
    public class MockCountryRepository : ICountryRepository
    {
        private List<CountryModel> Countries { get; set; }

        public MockCountryRepository()
        {
            var country = new CountryModel
            {
                Language = "en-us",
                CountryCode = "USA",
                CountryName = "United States"
            };
            Countries = new List<CountryModel> {country};
        }

        public List<CountryModel> GetAllCountries(string connectionString, int tenantId)
        {
            return Countries;
        }

        public CountryModel GetCountry(string countryCode, string connectionString, int tenantId)
        {
            return Countries[0];
        }
    }
}