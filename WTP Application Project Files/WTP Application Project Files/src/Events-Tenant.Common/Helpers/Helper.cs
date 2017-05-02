using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;
using Events_TenantUserApp.EF.TenantsDdEF6;

namespace Events_Tenant.Common.Helpers
{
    /// <summary>
    /// Helper class 
    /// </summary>
    public class Helper: IHelper
    {
        #region Private declarations

        private readonly ICountryRepository _countryRepository;
        private readonly ITenantsRepository _tenantsRepository;
        private readonly IVenuesRepository _venuesRepository;
        private readonly IVenueTypesRepository _venueTypesRepository;

        #endregion


        #region Constructor
        public Helper(ICountryRepository countryRepository, ITenantsRepository tenantsRepository, IVenuesRepository venuesRepository, IVenueTypesRepository venueTypesRepository)
        {
            _countryRepository = countryRepository;
            _tenantsRepository = tenantsRepository;
            _venuesRepository = venuesRepository;
            _venueTypesRepository = venueTypesRepository;
        }

        #endregion

        #region Get Connection strings

        /// <summary>
        /// Gets the basic sql connection string.
        /// </summary>
        /// <param name="databaseConfig">The database configuration.</param>
        /// <returns></returns>
        public string GetBasicSqlConnectionString(DatabaseConfig databaseConfig)
        {
            var connStrBldr = new SqlConnectionStringBuilder
            {
                UserID = databaseConfig.DatabaseUser,
                Password = databaseConfig.DatabasePassword,
                ApplicationName = "EntityFramework",
                ConnectTimeout = databaseConfig.ConnectionTimeOut
            };

            return connStrBldr.ConnectionString;
        }

        /// <summary>
        /// Gets the SQL connection string.
        /// </summary>
        /// <param name="databaseConfig">The database configuration.</param>
        /// <param name="catalogConfig">The catalog configuration.</param>
        /// <returns></returns>
        public string GetSqlConnectionString(DatabaseConfig databaseConfig, CatalogConfig catalogConfig)
        {
            var smmconnstr = GetBasicSqlConnectionString(databaseConfig);

            // Connection string with administrative credentials for the root database
            SqlConnectionStringBuilder connStrBldr = new SqlConnectionStringBuilder(smmconnstr)
            {
                DataSource =
                    databaseConfig.SqlProtocol + ":" + catalogConfig.CatalogServer + "," +
                    databaseConfig.DatabaseServerPort,
                InitialCatalog = catalogConfig.CatalogDatabase,
                ConnectTimeout = databaseConfig.ConnectionTimeOut
            };

            return connStrBldr.ConnectionString;
        }

        #endregion

        #region Public methods

        /// <summary>
        /// Register tenant shard
        /// </summary>
        /// <param name="tenantServerConfig">The tenant server configuration.</param>
        /// <param name="databaseConfig">The database configuration.</param>
        /// <param name="catalogConfig">The catalog configuration.</param>
        /// <param name="resetEventDate">If set to true, the events dates for all tenants will be reset </param>
        public void RegisterTenantShard(TenantServerConfig tenantServerConfig, DatabaseConfig databaseConfig, CatalogConfig catalogConfig, bool resetEventDate)
        {
            //get all database in devtenantserver
            var tenants = GetAllTenantNames(tenantServerConfig, databaseConfig);
            var connectionString = GetBasicSqlConnectionString(databaseConfig);

            foreach (var tenant in tenants)
            {
                var tenantId = GetTenantKey(tenant);
                if (Sharding.RegisterNewShard(tenant, tenantId, tenantServerConfig, databaseConfig, catalogConfig))
                {
                    // resets all tenants' event dates
                    if (resetEventDate)
                    {
                        #region EF6
                        //use EF6 since execution of Stored Procedure in EF Core for anonymous return type is not supported yet
                        using (var context = new TenantContext(Sharding.ShardMap, tenantId, connectionString))
                        {
                            context.Database.ExecuteSqlCommand("sp_ResetEventDates");
                        }
                        #endregion

                        #region EF core
                        //https://github.com/aspnet/EntityFramework/issues/7032
                        //using (var context = new TenantDbContext(Sharding.ShardMap, tenantId, connectionString))
                        //{
                        //     context.Database.ExecuteSqlCommand("sp_ResetEventDates");
                        //}
                        #endregion
                    }
                }
            }
        }

        /// <summary>
        /// Populates the tenant configs.
        /// </summary>
        /// <param name="tenant">The tenant.</param>
        /// <param name="host">The full address.</param>
        /// <param name="databaseConfig">The database configuration.</param>
        /// <param name="tenantConfig">The tenant configuration.</param>
        /// <returns></returns>
        public TenantConfig PopulateTenantConfigs(string tenant, string host, DatabaseConfig databaseConfig, TenantConfig tenantConfig)
        {
            //get user from url
            string user;
            if (host.Contains("localhost"))
            {
                user = "testuser";
            }
            else
            {
                string[] hostpieces = host.Split(new string[] { "." }, StringSplitOptions.RemoveEmptyEntries);
                user = hostpieces[2];
            }
             
            var connectionString = GetBasicSqlConnectionString(databaseConfig);

            var tenantDetails = _tenantsRepository.GetTenant(tenant);
            if (tenantDetails != null)
            {
                //get the venue details and populate in config settings
                var venueDetails = _venuesRepository.GetVenueDetails(connectionString, tenantDetails.TenantId);
                var venueTypeDetails = _venueTypesRepository.GetVenueType(venueDetails.VenueType, connectionString,
                    tenantDetails.TenantId);
                var countries = _countryRepository.GetAllCountries(connectionString, tenantDetails.TenantId);

                //get country language from db 
                var country = _countryRepository.GetCountry(venueDetails.CountryCode, connectionString, tenantDetails.TenantId);
                RegionInfo regionalInfo = new RegionInfo(country.Language);

                return new TenantConfig
                {
                    VenueName = venueDetails.VenueName,
                    BlobImagePath = tenantConfig.BlobPath + venueTypeDetails.VenueType + "-user.jpg",
                    EventTypeNamePlural = venueTypeDetails.EventTypeShortNamePlural.ToUpper(),
                    TenantId = tenantDetails.TenantId,
                    TenantName = venueDetails.DatabaseName,
                    BlobPath = tenantConfig.BlobPath,
                    Currency = regionalInfo.CurrencySymbol,
                    TenantCulture =
                        (!string.IsNullOrEmpty(venueTypeDetails.Language)
                            ? venueTypeDetails.Language
                            : tenantConfig.TenantCulture),
                    TenantCountries = countries,
                    TenantIdInString = tenantDetails.TenantIdInString,
                    User = user
                };
            }
            return null;
        }

        /// <summary>
        /// Converts the int key to bytes array.
        /// </summary>
        /// <param name="key">The key.</param>
        /// <returns></returns>
        public byte[] ConvertIntKeyToBytesArray(int key)
        {
            byte[] normalized = BitConverter.GetBytes(IPAddress.HostToNetworkOrder(key));

            // Maps Int32.Min - Int32.Max to UInt32.Min - UInt32.Max.
            normalized[0] ^= 0x80;

            return normalized;
        }

        #endregion

        #region Private methods

        /// <summary>
        /// Gets all tenant names from tenant server
        /// </summary>
        /// <param name="tenantServerConfig">The tenant server configuration.</param>
        /// <param name="databaseConfig">The database configuration.</param>
        /// <returns></returns>
        private List<string> GetAllTenantNames(TenantServerConfig tenantServerConfig, DatabaseConfig databaseConfig)
        {
            List<string> list = new List<string>();

            string conString = $"Server={databaseConfig.SqlProtocol}:{tenantServerConfig.TenantServer},{databaseConfig.DatabaseServerPort};Database={""};User ID={databaseConfig.DatabaseUser};Password={databaseConfig.DatabasePassword};Trusted_Connection=False;Encrypt=True;Connection Timeout={databaseConfig.ConnectionTimeOut};";

            using (SqlConnection con = new SqlConnection(conString))
            {
                con.Open();

                using (SqlCommand cmd = new SqlCommand("SELECT name from sys.databases WHERE name NOT IN ('master')", con))
                {
                    using (IDataReader dr = cmd.ExecuteReader())
                    {
                        while (dr.Read())
                        {
                            list.Add(dr[0].ToString());
                        }
                    }
                }
            }
            return list;
        }

        /// <summary>
        /// Generates the tenant Id using MD5 Hashing.
        /// </summary>
        /// <param name="tenantName">Name of the tenant.</param>
        /// <returns></returns>
        private int GetTenantKey(string tenantName)
        {
            var normalizedTenantName = tenantName.Replace(" ", string.Empty).ToLower();

            //Produce utf8 encoding of tenant name 
            var tenantNameBytes = Encoding.UTF8.GetBytes(normalizedTenantName);

            //Produce the md5 hash which reduces the size
            MD5 md5 = MD5.Create();
            var tenantHashBytes = md5.ComputeHash(tenantNameBytes);

            //Convert to integer for use as the key in the catalog 
            int tenantKey = BitConverter.ToInt32(tenantHashBytes, 0);

            return tenantKey;
        }
        #endregion
    }
}
