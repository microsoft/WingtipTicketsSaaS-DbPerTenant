using System.Collections.Generic;
using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Core.Repositories
{
    public class CountryRepository: BaseRepository, ICountryRepository
    {
        public List<CountryModel> GetAllCountries(string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                var allCountries = context.Countries;

                return allCountries.Select(country => new CountryModel
                {
                    CountryCode = country.CountryCode.Trim(),
                    Language = country.Language.Trim(),
                    CountryName = country.CountryName.Trim()
                }).ToList();
            }
        }

        public CountryModel GetCountry(string countryCode, string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                var countries = context.Countries.Where(x => x.CountryCode == countryCode);

                if (countries.Any())
                {
                    var country = countries.FirstOrDefault();
                    return new CountryModel
                    {
                        CountryCode = country.CountryCode.Trim(),
                        Language = country.Language.Trim(),
                        CountryName = country.CountryName.Trim()
                    };
                }
            }
            return null;
        }
    }
}