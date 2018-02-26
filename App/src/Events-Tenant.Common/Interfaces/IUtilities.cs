using Events_Tenant.Common.Utilities;

namespace Events_Tenant.Common.Interfaces
{
    public interface IUtilities
    {
        void RegisterTenantShard(TenantServerConfig tenantServerConfig, DatabaseConfig databaseConfig, CatalogConfig catalogConfig, bool resetEventDate);

        byte[] ConvertIntKeyToBytesArray(int key);
        string GetTenantStatus(int TenantId);
    }
}
