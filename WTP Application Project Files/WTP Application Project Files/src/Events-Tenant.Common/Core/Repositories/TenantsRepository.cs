using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Text.RegularExpressions;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Models;
using Events_TenantUserApp.EF.CatalogDB;

namespace Events_Tenant.Common.Core.Repositories
{
    public class TenantsRepository : ITenantsRepository
    {
        private readonly CatalogDbContext _catalogDbContext;

        public TenantsRepository(CatalogDbContext catalogDbContext)
        {
            _catalogDbContext = catalogDbContext;
        }

        public List<TenantModel> GetAllTenants()
        {
            var allTenantsList = _catalogDbContext.Tenants;

            return allTenantsList.Select(tenant => new TenantModel
            {
                ServicePlan = tenant.ServicePlan,
                TenantId = ConvertByteKeyIntoInt(tenant.TenantId),
                TenantName = tenant.TenantName
            }).ToList();
        }


        public TenantModel GetTenant(string tenantName)
        {
            var tenants = _catalogDbContext.Tenants.Where(i => Regex.Replace(i.TenantName.ToLower(), @"\s+", "") == tenantName);

            if (tenants.Any())
            {
                var tenant = tenants.FirstOrDefault();

                string tenantIdInString = BitConverter.ToString(tenant.TenantId);
                tenantIdInString = tenantIdInString.Replace("-", "");

                return new TenantModel
                {
                    ServicePlan = tenant.ServicePlan,
                    TenantName = tenant.TenantName,
                    TenantId = ConvertByteKeyIntoInt(tenant.TenantId),
                    TenantIdInString = tenantIdInString
                };
            }

            return null;
        }

        public bool Add(Tenants tenant)
        {
            _catalogDbContext.Tenants.Add(tenant);
            _catalogDbContext.SaveChanges();

            return true;
        }

        #region Private methods

        /// <summary>
        /// Converts the byte key into int.
        /// </summary>
        /// <param name="key">The key.</param>
        /// <returns></returns>
        private int ConvertByteKeyIntoInt(byte[] key)
        {
            // Make a copy of the normalized array
            byte[] denormalized = new byte[key.Length];

            key.CopyTo(denormalized, 0);

            // Flip the last bit and cast it to an integer
            denormalized[0] ^= 0x80;

            return IPAddress.HostToNetworkOrder(BitConverter.ToInt32(denormalized, 0));
        }
        #endregion

    }
}
