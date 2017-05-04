# Catalog Sync: script that synchronizes extended database meta data in the catalog with the current state of the system.

# IMPORTANT: script + supporting modules, dlls is intended to  be deployed as a continuous Web Job.

# IMPORTANT: The Service Principal used MUST have been created previously for this app in Active Directory 
# and given reader rights to resources in the WTP resource group.  See Deploy-CatalogSync.ps1

# Customize the following before deploying:
 
    #> Active Directory domain (see Azure portal, displayed in top right corner, typically in format "<...>.onmicrosoft.com")
    $domainName = "<domainName>"

    #> Azure Tenant Id
    $tenantId = "<tenantId>"

    #> Azure subscription ID for the subscription under which the WTP app is deployed 
    $subscriptionId = "<subscriptionId>"

    # Sync interval in seconds.   
    $interval = 60

# Sync goal: 
#   Ensure catalog has a near-current record of configuration of servers, pools and databases to enable 
#   DR to a recovery region with mirror servers, with same pool DTU, and database service objective configurations. 
# Sync principles:
#   - Sync is a continuous process, synchronizing at fixed intervals.
#   - Sync interval should be matched to typical rate of db creation such that, except in case of reinitialization of 
#     extended meta data, changes on each iteration will be few and infrequent. 
#   - Missing sync of a change to a server, database or pool will thus be unlikely, but if it occurs, DR will use prior config
#     or if pool or db is new, default configuration  and which will most likely be accurate or acceptable.
#     - given rate of changes, missing changes to dbs is unlikely, pools is very unlikely, servers is rare.         
#   - Sync is driven by database presence in catalog - no databases, no sync.
#     - from database location, identify all servers that house databases and sync those
#       - ignore servers that do not house registered databases 
#     - for each server in scope
#       - identify all registered dbs on the server and sync them 
#           this limits scope of ARM retrievals in case of large #s of databases
#           ignore non-registered databases (recovery will be driven by catalog registration info 
#       - identify all pools on the server and sync them 
#           includes pools not used by registered databases 

Import-Module $PSScriptRoot\Common\CatalogAndDatabaseManagement -Force
Import-Module $PSScriptRoot\WtpConfig -Force
Import-Module $PSScriptRoot\ProvisionConfig -Force
Import-Module $PSScriptRoot\UserConfig -Force

# Get cobfiguration  
$wtpUser = Get-UserConfig
$config = Get-Configuration
$provisionConfig = Get-ProvisionConfiguration

# Format the service principal login credential. 

# IMPORTANT: The Service principal MUST have been created previously in Active Directory and 
# given reader rights to resources in the WTP resource group.  See Deploy-CatalogSync.ps1

$userName = "http://" + $config.CatalogManagementAppNameStem + $wtpUser.Name + "@" + $DomainName
$password = $config.ServicePrincipalPassword
$pass = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object pscredential -ArgumentList ($userName, $pass)

# Login to Azure using the service principal
Login-AzureRmAccount -ServicePrincipal -Credential $cred -TenantId $TenantId

# Set the subscription 
$azureContext = Select-AzureRmSubscription -SubscriptionId $subscriptionId -ErrorAction Stop

# get the catalog 
$catalog = Get-Catalog -ResourceGroupName $WtpUser.ResourceGroupName -WtpUser $WtpUser.Name

# get the ARM location from the catalog database; assumes tenants deployed in the same region
$location = $catalog.Database.Location

## ---------------------------------------------------------------------------------------

Write-Output "Synchronizing databases with catalog at $interval second intervals..."

# start the web job continuous execution loop.  The web job sleeps between each iteration.  
# Job is stateless across loops - all resource-related variables are initialized in each iteration.

While (1 -eq 1)
{
    $loopStart = (Get-Date).ToUniversalTime()

    ## Synchronize servers

    # get tenant servers in the primary WTP region (Find-AzureRMResource restricts searches to the ARM cache)
    $servers = @()
    $servers += Get-AzureRMSqlServer -ResourceGroupName $wtpUser.ResourceGroupName | select | where Location -eq $location | select | where ServerName -match "$($provisionConfig.ServerNameStem)*"
    $servers = $servers | sort ServerName  

    $serversDict = @{}
    foreach ($server in $servers)
    {
        $serversDict += @{$server.ServerName = $server}
    }

    # get server entries in catalog
    $catalogServers = @()
    $catalogServers += Get-ExtendedServer -Catalog $catalog            
    $catalogServersDict = @{}
    foreach($catalogServer in $catalogServers)
    {
        $catalogServersDict += @{$catalogServer.ServerName = $catalogServer}
    }

    # synchronize catalog server entries with the current set of servers
    foreach($server in $servers)
    {
        if (-not $catalogServersDict.ContainsKey($server.ServerName))
        {
            # add server entry to catalog
            Set-ExtendedServer -Catalog $catalog -Server $server
        }

        # compare ARM server config with catalog entry
        # no additional config is held in catalog so this is not required   
    }

    # remove any catalog entries no longer present in ARM
    foreach ($catalogServer in $catalogServers)
    {
        if (-not $serversDict.ContainsKey($catalogServer.ServerName))
        {
            # remove the entry from the catalog
            Remove-ExtendedServer -Catalog $catalog -ServerName $catalogServer.ServerName
        }
    }

    ## Synchronize Elastic Pools

    # Build dictionary of all pool entries in the catalog
    $catalogElasticPools = @()
    $catalogElasticPools += Get-ExtendedElasticPool -Catalog $catalog

    $catalogElasticPoolsDict = @{}
    foreach($catalogElasticPool in $catalogElasticPools)
    {
        $compoundElasticPoolName = "$($catalogElasticPool.ServerName)/$($catalogElasticPool.ElasticPoolName)"
        $catalogElasticPoolsDict += @{$compoundElasticPoolName = $catalogElasticPool}
    }

    # get all current pools server by server
    $elasticPools = @()
    $elasticPoolsDict = @{}
    foreach ($server in $servers)
    { 
        $serverElasticPools = @()
        $serverElasticPools += Get-AzureRmSqlElasticPool `
                            -ResourceGroupName $wtpUser.ResourceGroupName `
                            -ServerName $server.ServerName

        foreach ($serverElasticPool in $serverElasticPools)
        {
            $elasticPools += $serverElasticPool
 
            $compoundElasticPoolName = "$($serverElasticPool.ServerName)/$($serverElasticPool.ElasticPoolName)"
            $elasticPoolsDict += @{$compoundElasticPoolName = $serverElasticPool}
        }
    }

    # synchronize catalog pool entries with the current pools
    foreach($elasticPool in $elasticPools)
    {
        # get the current count of buffer databases in the pool
        $elasticDatabases = @()
        $elasticDatabases += Get-AzureRmSqlElasticPoolDatabase `
                -ResourceGroupName $wtpUser.ResourceGroupName `
                -ServerName $ElasticPool.ServerName `
                -ElasticPoolName $ElasticPool.ElasticPoolName

        $bufferDatabases = $elasticDatabases | select | where DatabaseName -Match 'buffer*'                    
        
        # add entries for elastic pools not in the catalog
        $compoundElasticPoolName = "$($elasticPool.ServerName)/$($elasticPool.ElasticPoolName)"
        if (-not $catalogElasticPoolsDict.ContainsKey($compoundElasticPoolName))
        {
            # no elastic pool in catalog so add the elastic pool entry
            Set-ExtendedElasticPool `
                -Catalog $catalog `
                -ElasticPool $elasticPool `
                -BufferDatabases $bufferDatabases.Count
        }
        else
        {    
            $catalogElasticPool = $catalogElasticPoolsDict.$compoundElasticPoolName                 
            # elastic pool is in catalog so determine if its configuration has changed
            if (
                $catalogElasticPool.Edition -ne $elasticPool.Edition -or 
                $catalogElasticPool.Dtu -ne $elasticPool.Dtu -or
                $catalogElasticPool.DatabaseDtuMax -ne $elasticPool.DatabaseDtuMax -or
                $catalogElasticPool.DatabaseDtuMin -ne $elasticPool.DatabaseDtuMin -or
                $catalogElasticPool.StorageMB -ne $elasticPool.StorageMB -or
                $catalogElasticPool.BufferDatabases -ne $bufferDatabases.Count
            )                  
            {
                # configuration changes detected so update the pool entry in the catalog
                Set-ExtendedElasticPool `
                    -Catalog $catalog `
                    -ElasticPool $elasticPool `
                    -BufferDatabases $bufferDatabases.Count
            }
        }
    }

    # remove any catalog entries for elastic pools that no longer exist
    foreach ($catalogElasticPool in $catalogElasticPools)
    {
        $compoundElasticPoolName = "$($catalogElasticPool.ServerName)/$($catalogElasticPool.ElasticPoolName)"
        if (-not $elasticPoolsDict.ContainsKey($compoundElasticPoolName))
        {
            # remove the elastic pool entry from the catalog
            Remove-ExtendedElasticPool `
                -Catalog $catalog `
                -ServerName $catalogElasticPool.ServerName `
                -ElasticPoolName $catalogElasticPool.ElasticPoolName
        }
    }

    ## Synchronize databases 

    # Synchronization is based on the set registered in the catalog.  Buffer databases are synchronized only 
    # to produce the total on the elastic pool entry in the catalog.  Other databases are ignored. 


    # get all the tenant databases registered in the catalog
    $tenantDatabases =@()
    $tenantDatabases += Get-Shards -ShardMap $catalog.ShardMap
    $tenantDatabasesDict = @{}
    foreach ($tenantDatabase in $tenantDatabases)
    {
        $compoundDatabaseName = "$($tenantDatabase.Location.Server.split('.',2)[0])/$($tenantDatabase.Location.Database)" 
        $tenantDatabasesDict += @{$compoundDatabaseName = $tenantDatabase}
    }

    if ($tenantDatabases.Count -ge 1)
    {
        # get the distinct tenant server names (from the database location property)
        $tenantServerNames = @()  
        $tenantServerNames += ($tenantDatabases `
            | Select -ExpandProperty Location `
            | Select -ExpandProperty Server `
            | Get-Unique).split('.', 2)[0] `
            | sort             

        # synchronize databases on a server-basis to limit scale of actions (max 5000 dbs/server)
        foreach($tenantServerName in $tenantServerNames)
        {
            # check the server exists among the servers in ARM
            if (-not $serversDict.ContainsKey($tenantServerName))
            {
                Write-output "ERROR: Server '$tenantServerName' referenced on one or more databases in catalog is not in ARM"
                continue
            }          
                                         
            # get the names of databases on this server registered in the catalog
            $tenantDatabaseNames = @()
            $tenantDatabaseNames += ($tenantDatabases `
                | where {($_.Location.Server).split('.',2)[0] -eq $tenantServerName} `
                | select -ExpandProperty Location `
                | select -ExpandProperty Database `
                | sort)
            
            # get the current databases on the this server
            $serverDatabases = @()
            $serverDatabases += Get-AzureRmSqlDatabase `
                    -ResourceGroupName $WtpUser.ResourceGroupName `
                    -ServerName $tenantServerName `
                    |where {$_.DatabaseName -ne 'master'} `
                    |sort $_.DatabaseName
        
            # If no databases found on server"
            if ($serverDatabases.count -lt 1)
            {
                # this may result from differences in timing between actions on the databases and the catalog   
                Write-Output "ERROR: no databases found for server '$tenantServerName'"
            }
            else
            {
                $serverDatabasesDict = @{}
                foreach ($serverDatabase in $serverDatabases)
                {
                    $serverDatabasesDict += @{$serverDatabase.DatabaseName = $serverDatabase}
                }

                # get database entries from catalog for the current server
                $catalogDatabases = @()
                $catalogDatabases += Get-ExtendedDatabase -Catalog $catalog -ServerName $tenantServerName
                $catalogDatabasesDict = @{}
                foreach($catalogDatabase in $catalogDatabases)
                {
                    $catalogDatabasesDict += @{$catalogDatabase.DatabaseName = $catalogDatabase}
                }

                # validate that databases registered in the catalog have an extended databases entry    
                foreach ($tenantDatabaseName in $tenantDatabaseNames)
                {
                    # if extended database entry exists for current tenant database
                    if ($catalogDatabasesDict.ContainsKey($tenantDatabaseName))
                    {
                        # verify that the database exists 
                        if ($serverDatabasesDict.ContainsKey($tenantDatabaseName))
                        {
                            # database entry exists
                            $catalogDatabase = $catalogDatabasesDict.$tenantDatabaseName
                            $serverDatabase = $serverDatabasesDict.$tenantDatabaseName
                    
                            # determine if the extended database entry in the catalog is different from database  
                            if ($catalogDatabase.ServiceObjective -ne $serverDatabase.CurrentServiceObjectiveName -or
                                $catalogDatabase.ElasticPoolName -ne $serverDatabase.ElasticPoolName)
                            {
                                # update the extended database entry in the catalog
                                Set-ExtendedDatabase -Catalog $catalog -Database $serverDatabase                            
                                Write-Verbose "Updated extended meta data for database '$tenantDatabase'"
                            }
                        }
                        else
                        {
                            # database was not found but is present in catalog, may be a timing difference                       
                            Write-Output "ERROR: database '$tenantDatabase' present in catalog but not found in ARM"
                        }
                    }
                    else
                    # no extended database entry for the tenant database registered in the catalog, create one if database exists
                    {
                        # if database exists, create extended database entry based on the actual database configuration
                        if ($serverDatabasesDict.ContainsKey($tenantDatabaseName))
                        {
                            Set-ExtendedDatabase -Catalog $catalog -Database $serverDatabasesDict.$tenantDatabaseName
                            Write-Verbose "Created extended meta data for database '$tenantDatabaseName'"

                        }
                        # if database doesn't exist it's an error
                        else
                        {
                            # likely a timing issue
                            Write-Output "ERROR: no database found for database '$tenantDatabaseName' registered in catalog"
                        }
                    }
                }
            } 
        }
    }
    else
    {
        # no databases in catalog so no synchronization required
    }
    
    $duration =  [math]::Round(((Get-Date).ToUniversalTime() - $loopStart).Seconds)    
    if ($duration -lt $interval)
    { 
        Write-Verbose "Sleeping for $($interval - $duration) seconds"
        Start-Sleep ($interval - $duration)
    }
}
