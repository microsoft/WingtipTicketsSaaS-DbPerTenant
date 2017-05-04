


<#
.SYNOPSIS
    Returns default configuration values that will be used by the Wingtip Tickets Platform application
#>
function Get-Configuration
{
    $configuration = @{`
        TemplatesLocationUrl = "https://wtpdeploystorageaccount.blob.core.windows.net/templates"
        TenantDatabaseTemplate = "tenantdatabasetemplate.json"
        TenantDatabaseCopyTemplate = "tenantdatabasecopytemplate.json"
        TenantDatabaseBatchTemplate = "tenantdatabasebatchtemplate.json"
        TenantDatabaseCopyBatchTemplate = "tenantdatabasecopybatchtemplate.json"
        WebApplicationTemplate = "webapplicationtemplate.json"
        LogAnalyticsWorkspaceTemplate = "loganalyticsworkspacetemplate.json"
        LogAnalyticsWorkspaceNameStem = "wtploganalytics-"
        LogAnalyticsDeploymentLocation = "westcentralus"
        DatabaseAndBacpacTemplate = "databaseandbacpactemplate.json"
        TenantBacpacUrl = "https://wtpdeploystorageaccount.blob.core.windows.net/wingtip-bacpacsvold/wingtiptenantdb.bacpac"
        GoldenTenantDatabaseName = "baseTenantDB"
        CatalogDatabaseName = "tenantcatalog"
        CatalogServerNameStem = "catalog-"
        TenantServerNameStem = "tenants1-"
        TenantPoolNameStem = "Pool"
        CatalogShardMapName = "tenantcatalog"
        CatalogAdminUserName = "developer"
        CatalogAdminPassword = "P@ssword1"
        TenantAdminUserName = "developer"
        TenantAdminPassword = "P@ssword1"
        CatalogManagementAppNameStem = "catalogmanagement-"
        CatalogManagementAppSku = "standard"
        CatalogManagementAppSkuCode = "S1"
        CatalogManagementAppWorkerSize = 0
        CatalogSyncWebJobNameStem = "catalogsync-"
        AutoProvisionWebJobNameStem = "autoprovision-"
        ServicePrincipalPassword = "P@ssword1"
        JobAccount = "jobaccount"
        JobAccountDatabaseName = "jobaccount"
        TenantAnalyticsDatabaseName = "tenantanalytics"
        AdhocAnalyticsDatabaseName = "adhocanalytics"
        AdhocAnalyticsDatabaseServiceObjective = "S0"
        AdhocAnalyticsBacpacUrl = "https://wtpdeploystorageaccount.blob.core.windows.net/wingtip-bacpacsvold/adhoctenantanalytics.bacpac"
        StorageKeyType = "SharedAccessKey"
        StorageAccessKey = (ConvertTo-SecureString -String "?" -AsPlainText -Force)
        DefaultVenueType = "multipurpose"
        TenantNameBatch = @(
            ("Poplar Dance Academy","dance"),
            ("Blue Oak Jazz Club","blues"),
            ("Juniper Jammers Jazz","jazz"),
            ("Sycamore Symphony","classicalmusic"),
            ("Hornbeam HipHop","dance"),
            ("Mahogany Soccer","soccer"),
            ("Lime Tree Track","motorracing"),
            ("Balsam Blues Club","blues"),
            ("Tamarind Studio","dance"),
            ("Star Anise Judo", "judo"),
            ("Cottonwood Concert Hall","classicalmusic"),
            ("Mangrove Soccer Club","soccer"),
            ("Foxtail Rock","rockmusic"),
            ("Osage Opera","opera"),
            ("Papaya Players","soccer"),
            ("Magnolia Motor Racing","motorracing"),
            ("Sorrel Soccer","soccer")       
            )
        }
    return $configuration
}
