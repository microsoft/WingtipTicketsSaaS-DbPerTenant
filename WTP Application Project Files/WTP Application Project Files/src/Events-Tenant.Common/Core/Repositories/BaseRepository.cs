using Events_Tenant.Common.Utilities;
using Events_TenantUserApp.EF.TenantsDB;

namespace Events_Tenant.Common.Core.Repositories
{
    public class BaseRepository
    {
        #region Create context

        public TenantDbContext CreateContext(string connectionString, int tenantId)
        {
          return  new TenantDbContext(Sharding.ShardMap, tenantId, connectionString);
        }

        #endregion

    }
}
