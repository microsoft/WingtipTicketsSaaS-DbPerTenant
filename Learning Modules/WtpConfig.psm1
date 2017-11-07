# Get and/or set PowerShell session to only run scripts targeting dbpertenant Wingtip deployment 
$Global:ErrorActionPreference = "Stop"
$scriptsTarget = 'dbpertenant'

if ($Global:WingtipScriptsTarget -and ($Global:WingtipScriptsTarget -ne $scriptsTarget))
{
    throw "This PowerShell session is setup to only run scripts targeting Wingtip '$Global:WingtipScriptsTarget' architecture. Open up a new PowerShell session to run scripts targeting Wingtip '$scriptsTarget' architecture."  
}
elseif (!$Global:WingtipScriptsTarget)
{
    Write-Verbose "Configuring PowerShell session to only run scripts targeting Wingtip '$scriptsTarget' architecture ..."
    Set-Variable WingtipScriptsTarget -option Constant -value $scriptsTarget -scope global
}

<#
.SYNOPSIS
    Returns default configuration values that will be used by the Wingtip Tickets Platform application
#>
function Get-Configuration
{
    $configuration = @{`
        TemplatesLocationUrl = "https://wingtipsaas.blob.core.windows.net/templates"
        TenantDatabaseTemplate = "tenantdatabasetemplate.json"
        TenantDatabaseCopyTemplate = "tenantdatabasecopytemplate.json"
        TenantDatabaseBatchTemplate = "tenantdatabasebatchtemplate.json"
        TenantDatabaseCopyBatchTemplate = "tenantdatabasecopybatchtemplate.json"
        WebApplicationTemplate = "webapplicationtemplate.json"
        WebApplicationRecoveryTemplate = "webappRecoveryTemplate.json"
        LogAnalyticsWorkspaceTemplate = "loganalyticsworkspacetemplate.json"
        LogAnalyticsWorkspaceNameStem = "wtploganalytics-"
        LogAnalyticsDeploymentLocation = "westcentralus"
        DatabaseAndBacpacTemplate = "databaseandbacpactemplate.json"
        TenantBacpacUrl = "https://wingtipsaas.blob.core.windows.net/bacpacs/wingtiptenantdb.bacpac"
        EventsAppNameStem = "eventswtp-"
        RecoverySuffix = "-recovery"
        GoldenTenantDatabaseName = "baseTenantDB"
        CatalogDatabaseName = "tenantcatalog"
        CatalogServerNameStem = "catalog-"
        CatalogRecoveryTemplate = "tenantcatalogrecoverytemplate.json"
        TenantServerNameStem = "tenants1-"
        TenantElasticPoolRestoreBatchTemplate = "tenantelasticpoolrecoverybatchtemplate.json"
        TenantDatabaseRestoreBatchTemplate = "tenantdatabaserecoverybatchtemplate.json"
        TenantServerRestoreBatchTemplate = "tenantserverrecoverybatchtemplate.json"
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
        ServicePrincipalPassword = "P@ssword1"
        NewTenantResourcesProvisioningTemplate = "newtenantresourcestemplate.json"
        JobAccount = "jobaccount"
        JobAccountDatabaseName = "jobaccount"
        JobAccountDatabaseServiceObjective = "S2"
        JobAccountCredentialName = "mydemocred"
        TenantAnalyticsDatabaseName = "tenantanalytics"
        TenantAnalyticsCSDatabaseName = "tenantanalytics-cs"
        TenantAnalyticsDWDatabaseName = "tenantanalytics-dw"
        AdhocAnalyticsDatabaseName = "adhocanalytics"
        AdhocAnalyticsDatabaseServiceObjective = "S0"
        AdhocAnalyticsBacpacUrl = "https://wtpdeploystorageaccount.blob.core.windows.net/wingtip-bacpacsvold/adhoctenantanalytics.bacpac"
        SearchDatabaseName = "tenantsearch"  
        SearchDatabaseServiceObjective = "S0"              
        StorageKeyType = "SharedAccessKey"
        StorageAccessKey = (ConvertTo-SecureString -String "?" -AsPlainText -Force)
        DefaultVenueType = "multipurpose"
        TenantNameBatch = @(
            ("Poplar Dance Academy","dance","98402"),
            ("Blue Oak Jazz Club","blues","98201"),
            ("Juniper Jammers Jazz","jazz","98032"),
            ("Sycamore Symphony","classicalmusic","98004"),
            ("Hornbeam HipHop","dance","98036"),
            ("Mahogany Soccer","soccer","98032"),
            ("Lime Tree Track","motorracing","98115"),
            ("Balsam Blues Club","blues","98104"),
            ("Tamarind Studio","dance","98072"),
            ("Star Anise Judo", "judo","98103"),
            ("Cottonwood Concert Hall","classicalmusic","98402"),
            ("Mangrove Soccer Club","soccer","98036"),
            ("Foxtail Rock","rockmusic","98107"),
            ("Osage Opera","opera","98101"),
            ("Papaya Players","soccer","98116"),
            ("Magnolia Motor Racing","motorracing","98040"),
            ("Sorrel Soccer","soccer","98188")       
            )
        }
    return $configuration
}
