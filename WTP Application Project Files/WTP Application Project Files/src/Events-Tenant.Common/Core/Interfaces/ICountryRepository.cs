using System.Collections.Generic;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Core.Interfaces
{
    public interface ICountryRepository
    {
        List<CountryModel> GetAllCountries(string connectionString, int tenantId);

        CountryModel GetCountry(string countryCode, string connectionString, int tenantId);
    }
}
