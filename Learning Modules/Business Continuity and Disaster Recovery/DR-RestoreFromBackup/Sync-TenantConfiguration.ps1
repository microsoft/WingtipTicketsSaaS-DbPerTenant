<#
.SYNOPSIS
  Synchronizes tenant resource configuration into the catalog database 

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

# Get the tenant catalog 
$catalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name

Write-Output "Synchronizing tenant resources with catalog at $interval second intervals..."

# Start continuous execution loop. The script sleeps between each iteration.
while (1 -eq 1)
{
    # Get the active tenant catalog 
    $catalog = Get-Catalog -ResourceGroupName $wtpUser.ResourceGroupName -WtpUser $wtpUser.Name
    Write-Output "Acquired tenant catalog: '$($catalog.Database.ServerName)/$($catalog.Database.DatabaseName)'"
    
    $loopStart = (Get-Date).ToUniversalTime()
    $tenantShardLocations = (Get-TenantDatabaseLocations $catalog).Location | Select -Property "Server", "Database"
    $tenantResources = @()
    
    #-------------------------------------------------------[Synchronize servers]------------------------------------------------------------
    Write-Output "Synchronizing tenant servers..."
    
    $servers = @()

    # Get tenant servers 
    foreach ($tenantShard in $tenantShardLocations)
    {
        $fullyQualifiedTenantServerName = $tenantShard.Server
        $tenantServerName = $tenantShard.Server.Split('.')[0]
        $tenantDatabaseName = $tenantShard.Database
        $tenantResources += New-Object PSObject -Property @{ServerName = $tenantServerName; DatabaseName = $tenantDatabaseName}

        # Add tenant server to server list if not previously seen 
        if ($servers.ServerName -notcontains $tenantServerName)
        {
            $serverResourceGroup = (Get-AzureRmResource -Name $tenantServerName -ResourceType "Microsoft.Sql/servers").ResourceGroupName
            $servers += Get-AzureRMSqlServer -ResourceGroupName $serverResourceGroup -ServerName $tenantServerName
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

    #-----------------------------------------------------[Synchronize databases]------------------------------------------------------------
    Write-Output "Synchronizing tenant databases..."
    
    # Get all tenant databases
    $tenantDatabases = @()
    foreach ($resource in $tenantResources)
    {
        $databaseName = "$($resource.ServerName)/$($resource.DatabaseName)"
        $databaseResourceGroup = (Get-AzureRmResource -Name $databaseName -ResourceType "Microsoft.Sql/servers/databases").ResourceGroupName
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

    # Sleep if elapsed time is less than the input interval 
    $duration =  [math]::Round(((Get-Date).ToUniversalTime() - $loopStart).Seconds)    
    if ($duration -lt $interval)
    { 
        Write-Output "Sleeping for $($interval - $duration) seconds"
        Write-Output "---"
        Start-Sleep ($interval - $duration)
    }
}
