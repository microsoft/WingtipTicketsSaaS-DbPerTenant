
<#
.SYNOPSIS
    Returns default provisioning config values that will be used by the auto-provisioning WebJobs
#>
function Get-ProvisionConfiguration
{
    $config = @{`
        ServerNameStem = 'tenants'
        ServerElasticPoolsMax = 2
        ElasticPoolNameStem = 'Pool'
        ElasticPoolEdition = 'Standard'
        ElasticPoolDtu = 50
        ElasticPoolDatabaseDtuMax = 50
        ElasticPoolDatabaseDtuMin = 0
        ElasticPoolDatabasesMax = 25
        BufferDatabases = 20
        BufferDatabaseNameStem = 'buffer-'
        }
    return $config
}
