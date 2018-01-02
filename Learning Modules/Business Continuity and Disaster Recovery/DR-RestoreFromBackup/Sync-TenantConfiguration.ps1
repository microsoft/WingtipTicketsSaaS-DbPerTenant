<#
.SYNOPSIS
  Synchronizes tenant server and pool configuration into the catalog database 

.DESCRIPTION
  This script ensures that the Wingtip tenant catalog has the most current record of configuration of tenant servers, pools and databases.
  This enables disaster recovery to a recovery region with mirror servers and pools that match the initial configuration. 

.PARAMETER Interval
  The catalog sync interval in seconds

.EXAMPLE
  [PS] C:\>.\Sync-TenantConfiguration.ps1 
#>
[cmdletbinding()]
param (
    [parameter(Mandatory=$false)]
    [int] $Interval = 60,

    # NoEcho stops the output of the signed in user to prevent double echo  
    [parameter(Mandatory=$false)]
    [switch] $NoEcho
)

#----------------------------------------------------------[Initialization]----------------------------------------------------------

Import-Module $PSScriptRoot\..\..\Common\CatalogAndDatabaseManagement -Force
Import-Module $PSScriptRoot\..\..\WtpConfig -Force
Import-Module $PSScriptRoot\..\..\UserConfig -Force

# Stop execution on error 
$ErrorActionPreference = "Stop"

# Get deployment configuration  
$wtpUser = Get-UserConfig
$config = Get-Configuration

# Get Azure credentials
$credentialLoad = Import-AzureRmContext -Path "$env:TEMP\profile.json"
if (!$credentialLoad)
{
    Initialize-Subscription -NoEcho:$NoEcho.IsPresent
}

# Get the active tenant catalog 
$catalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name

# Initialize catalog database sync tables
& $PSScriptRoot\..\..\Utilities\Initialize-CatalogSyncTables.ps1 `
    -WtpResourceGroupName $wtpUser.ResourceGroupName `
    -WtpUser $wtpUser.Name 

# Get the ARM location from the catalog database; assumes tenants deployed in the same region
# $location = $catalog.Database.Location.ToLower() -replace '\s',''

Write-Output "Synchronizing tenant resources with catalog at $interval second intervals..."

# Start continuous execution loop. The script sleeps between each iteration.
while (1 -eq 1)
{
    # Get the active tenant catalog 
    $catalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name
    Write-Output "Acquired active tenant catalog: '$($catalog.Database.ServerName)/$($catalog.Database.DatabaseName)'"
    
    $loopStart = (Get-Date).ToUniversalTime()
    $tenantShardLocations = (Get-TenantDatabaseLocations $catalog).Location | Select -Property "Server", "Database"
    $tenantResources = @()
    
    #-------------------------------------------------------[Synchronize servers]------------------------------------------------------------
    Write-Output "Synchronizing tenant servers..."
    
    $servers = @()
    $dnsRetry = $false 

    # Get tenant servers 
    foreach ($tenantShard in $tenantShardLocations)
    {
        try
        {
            # Resolve tenant server name from alias stored in shard 
            $tenantServerName = Get-ServerNameFromAlias $tenantShard.Server
            $tenantDatabaseName = $tenantShard.Database
            $tenantResources += New-Object PSObject -Property @{ServerName = $tenantServerName; DatabaseName = $tenantDatabaseName}

            # Add tenant server to server list if not previously seen 
            if ($servers.ServerName -notcontains $tenantServerName)
            {
                $serverResourceGroup = (Find-AzureRmResource -ResourceNameEquals $tenantServerName -ResourceType "Microsoft.Sql/servers").ResourceGroupName
                $servers += Get-AzureRMSqlServer -ResourceGroupName $serverResourceGroup -ServerName $tenantServerName
            }   
        }
        catch
        {
            #Retry DNS query at later time to resolve tenant server name from alias
            $dnsRetry = $true 
        } 
    }
    
    $servers = $servers | sort ServerName 

    # Get server entries already in the catalog
    $syncedTenantServers = @()
    $syncedTenantServers += Get-ExtendedServer -Catalog $catalog           

    # Add new server entries to catalog if they do not exist
    foreach ($server in $servers)
    {
        if ($syncedTenantServers.ServerName -notcontains $server.ServerName)
        {
            # add server entry to catalog
            Set-ExtendedServer -Catalog $catalog -Server $server
        }  
    }

    # Remove any catalog server entries representing servers that no longer hold tenants
    foreach ($syncedTenantServer in $syncedTenantServers)
    {
        # Do not remove servers that will be used for disaster recovery 
        if (($servers.ServerName -notcontains $syncedTenantServer.ServerName) -and ($syncedTenantServer.RecoveryState -notmatch 'restored$|complete$') -and (!$dnsRetry))
        {
            # remove the entry from the catalog
            Remove-ExtendedServer -Catalog $catalog -ServerName $syncedTenantServer.ServerName
        }
    }

    #----------------------------------------------------[Synchronize Elastic Pools]------------------------------------------------------------
    Write-Output "Synchronizing tenant elastic pools..."
    
    # Get all tenant elastic pools server by server 
    $elasticPools = @()
    foreach ($server in $servers)
    {
        $elasticPools += Get-AzureRmSqlElasticPool -ResourceGroupName $server.ResourceGroupName -ServerName $server.ServerName
    }

    # Add compound pool name to Azure pool entries 
    foreach ($poolEntry in $elasticPools)
    {
        $poolEntry | Add-Member "compoundElasticPoolName" "$($poolEntry.ServerName)/$($poolEntry.ElasticPoolName)"
    }

    # Get elastic pool entries already in the catalog 
    $syncedElasticPools = @()
    $syncedElasticPools += Get-ExtendedElasticPool -Catalog $catalog

    # Add compound pool name property to synced entries
    foreach ($poolEntry in $syncedElasticPools)
    {
        $poolEntry | Add-Member "compoundElasticPoolName" "$($poolEntry.ServerName)/$($poolEntry.ElasticPoolName)"
    }

    # Add new elastic pool entries or update existing pool entries in tenant catalog
    foreach ($elasticPool in $elasticPools)
    {
        # Add entries for elastic pools not in the catalog
        if ($syncedElasticPools.compoundElasticPoolName -notcontains $elasticPool.compoundElasticPoolName)
        {
            Set-ExtendedElasticPool -Catalog $catalog -ElasticPool $elasticPool
        }
        # Sync any configuration changes for elastic pools already in the catalog 
        elseif ($syncedElasticPools.compoundElasticPoolName -contains $compoundElasticPoolName)
        {
            $syncedElasticPool = $syncedElasticPools | Where-Object {$_.ServerName -eq $elasticPool.ServerName -and $_.ElasticPoolName -eq $elasticPool.ElasticPoolName}
            
            # Check if elastic pool configuration has changed 
            if
            (
                $syncedElasticPool.Edition -ne $elasticPool.Edition -or
                $syncedElasticPool.Dtu -ne $elasticPool.Dtu -or 
                $syncedElasticPool.DatabaseDtuMax -ne $elasticPool.DatabaseDtuMax -or
                $syncedElasticPool.DatabaseDtuMin -ne $elasticPool.DatabaseDtuMin -or
                $syncedElasticPool.StorageMB -ne $elasticPool.StorageMB 
               
            )
            {
                Set-ExtendedElasticPool -Catalog $catalog -ElasticPool $elasticPool
            }           
        }
    }

    # Remove any catalog entries for elastic pools that no longer exist
    foreach ($syncedElasticPool in $syncedElasticPools)
    {
        # Do not remove elastic pools that will be used for disaster recovery 
        if (($elasticPools.compoundElasticPoolName -notcontains $syncedElasticPool.compoundElasticPoolName) -and ($syncedElasticPool.RecoveryState -NotIn "restored", "complete"))
        {
            # remove the elastic pool entry from the catalog
            Remove-ExtendedElasticPool -Catalog $catalog -ServerName $syncedElasticPool.ServerName -ElasticPoolName $syncedElasticPool.ElasticPoolName
        }
    }

    #-----------------------------------------------------[Synchronize databases]------------------------------------------------------------
    Write-Output "Synchronizing tenant databases..."
    
    # Get all tenant databases
    $tenantDatabases = @()
    foreach ($resource in $tenantResources)
    {
        $databaseName = "$($resource.ServerName)/$($resource.DatabaseName)"
        $databaseResourceGroup = (Find-AzureRmResource -ResourceNameEquals $databaseName -ResourceType "Microsoft.Sql/servers/databases").ResourceGroupName
        $tenantDatabases += Get-AzureRmSqlDatabase -ResourceGroupName $databaseResourceGroup -ServerName $resource.ServerName -DatabaseName $resource.DatabaseName
    }
    $tenantDatabases = $tenantDatabases | sort DatabaseName

    # Add compound database name to Azure database entries 
    foreach ($dbEntry in $tenantDatabases)
    {
        $dbEntry | Add-Member "compoundDatabaseName" "$($dbEntry.ServerName)/$($dbEntry.DatabaseName)"
    }

    # Get database entries already in the catalog 
    $syncedDatabases = @()
    $syncedDatabases += Get-ExtendedDatabase -Catalog $catalog

    # Add compound database name to synced database entries
    foreach ($dbEntry in $syncedDatabases)
    {
        $dbEntry | Add-Member "compoundDatabaseName" "$($dbEntry.ServerName)/$($dbEntry.DatabaseName)"
    }

    # Add new database entires or update existing database entries in the tenant catalog
    foreach ($tenantDatabase in $tenantDatabases)
    {
        # Add entries for tenant databases not in the catalog 
        if ($syncedDatabases.compoundDatabaseName -notcontains $tenantDatabase.compoundDatabaseName)
        {
            Set-ExtendedDatabase -Catalog $catalog -Database $tenantDatabase
        }
        # Sync any configuration changes for tenant databases already in the catalog
        elseif ($syncedDatabases.compoundDatabaseName -contains $tenantDatabase.compoundDatabaseName)
        {
            $syncedDatabase = $syncedDatabases | Where-Object {$_.compoundDatabaseName -eq $tenantDatabase.compoundDatabaseName}

            # Check if database configuration has changed 
            if
            (
                $syncedDatabase.ServiceObjective -ne $tenantDatabase.CurrentServiceObjectiveName -or
                $syncedDatabase.ElasticPoolName -ne $tenantDatabase.ElasticPoolName
            )
            {
                Set-ExtendedDatabase -Catalog $catalog -Database $tenantDatabase
            }
        }
    }

    # Remove any catalog entries for tenant databases that no longer exist 
    foreach ($syncedDatabase in $syncedDatabases)
    {
        # Do not remove databases that will be used for disaster recovery 
        if (($tenantDatabases.compoundDatabaseName -notcontains $syncedDatabase.compoundDatabaseName) -and ($syncedDatabase.RecoveryState -NotIn "restored", "recovered", "complete"))
        {
            # remove the tenant database entry from the catalog
            Remove-ExtendedDatabase -Catalog $catalog -ServerName $syncedDatabase.ServerName -DatabaseName $syncedDatabase.DatabaseName
        }
    }

    # Sleep if elapsed time is less than the input interval 
    $duration =  [math]::Round(((Get-Date).ToUniversalTime() - $loopStart).Seconds)    
    if ($duration -lt $interval)
    { 
        Write-Output "Sleeping for $($interval - $duration) seconds"
        Write-Output "---"
        Start-Sleep ($interval - $duration)
    }
}
