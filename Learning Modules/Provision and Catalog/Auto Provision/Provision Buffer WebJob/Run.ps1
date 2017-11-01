# WebJob that replenishes buffer databases on WTP tenant servers for later allocation to tenants.

# IMPORTANT: The Service Principal used MUST have been created previously for this app in Active Directory 
# and given reader rights to resources in the WTP resource group.  See Deploy-CatalogSync.ps1

# Provide values for the following before deploying the webjob into the app sevice:
 
    #> Active Directory domain (see Azure portal, displayed in top right corner, typically in format "<...>.onmicrosoft.com")
    $domainName = "<domainName>"

    #> Azure Tenant Id
    $tenantId = "<tenantId>"

    #> Azure subscription ID for the subscription under which the WTP app is deployed 
    $subscriptionId = "<subscriptionId>"

    # Sync interval in seconds.   
    $interval = 60

## ------------------------------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

Import-Module $PSScriptRoot\Common\CatalogAndDatabaseManagement -Force
Import-Module $PSScriptRoot\Common\SubscriptionManagement -Force
Import-Module $PSScriptRoot\WtpConfig -Force
Import-Module $PSScriptRoot\ProvisionConfig -Force
Import-Module $PSScriptRoot\UserConfig -Force


# Get the resource group and user names used when the WTP application was deployed from UserConfig.psm1.  
$wtpUser = Get-UserConfig

# Get application configuration
$config = Get-Configuration

# Get auto provisioning defaults
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

# Get the catalog 
$catalog = Get-Catalog -ResourceGroupName $WtpUser.ResourceGroupName -WtpUser $WtpUser.Name

$location = $catalog.Database.Location.Replace(" ","").ToLower() 

## ---------------------------------------------------------------------------------------
<#
.SYNOPSIS
    Returns the tenant pool with the greatest number of empty database slots in a region 
#>
function Get-AvailableElasticPool {
    param(

        [parameter(Mandatory=$true)]
        [String]$Location
    )
    $Location = $Location.Replace(" ","").ToLower()

    $provisionConfig = Get-ProvisionConfiguration

    # get pool in region with the greatest number of available database slots
    $commandText = " 
        SELECT TOP 1 ep.ServerName, ep.ElasticPoolName, ep.Edition, ep.Dtu, ep.DatabaseDtuMax, ep.DatabaseDtuMin, ep.StorageMB, ep.DatabasesMax, ep.BufferDatabases, ep.[State], DatabasesMax - BufferDatabases - ISNULL(TenantDatabaseCount,0) AS AvailableSlots  
        FROM 
            ElasticPools as ep
            INNER JOIN Servers AS s ON s.ServerName = ep.serverName
            LEFT OUTER JOIN (
                SELECT ServerName, ElasticPoolName, Count(*) AS TenantDatabaseCount FROM Databases 
                GROUP BY ServerName, ElasticPoolName) as epd ON epd.ServerName = ep.ServerName AND epd.ElasticPoolName = ep.ElasticPoolName 
        WHERE 
            s.Location = '$Location' AND
            (DatabasesMax - BufferDatabases - ISNULL(TenantDatabaseCount,0) > 0)
        ORDER BY 
            (DatabasesMax - BufferDatabases - ISNULL(TenantDatabaseCount,0)) DESC "
        
    
    $availableElasticPool = Invoke-SqlAzureWithRetry `
        -ServerInstance ($config.CatalogServerNameStem + $wtpUser.Name + ".database.windows.net") `
        -DatabaseName $config.CatalogDatabaseName `
        -Query $commandText `
        -UserName $config.CatalogAdminUserName `
        -Password $config.CatalogAdminPassword 
        
    return $availableElasticPool
}


function Get-AvailableServer {
    param(

        [parameter(Mandatory=$true)]
        [String]$Location
    )

    $Location = $Location.Replace(" ","").ToLower()

    $provisionConfig = Get-ProvisionConfiguration

    # get server in region with the greatest number of available pool slots
    $commandText = " 
        SELECT TOP 1 s.ServerName, s.ElasticPoolsMax - ISNULL(sep.ElasticPoolCount,0) AS AvailablePoolSlots  
        FROM 
            Servers as s
            LEFT OUTER JOIN (
                SELECT ServerName, COUNT(*) AS ElasticPoolCount FROM ElasticPools
                GROUP BY ServerName) AS sep ON S.ServerName = sep.ServerName 
        WHERE 
            s.Location = '$Location' AND
            s.ElasticPoolsMax - ISNULL(sep.ElasticPoolCount,0) > 0
        ORDER BY
            (s.ElasticPoolsMax - ISNULL(sep.ElasticPoolCount,0)) DESC
        "
    
    $availableServer = Invoke-SqlAzureWithRetry `
        -ServerInstance ($config.CatalogServerNameStem + $wtpUser.Name + ".database.windows.net") `
        -DatabaseName $config.CatalogDatabaseName `
        -Query $commandText `
        -UserName $config.CatalogAdminUserName `
        -Password $config.CatalogAdminPassword 
        
    return $availableServer
}


function Get-TargetElasticPool{
    param (
        [parameter(Mandatory=$true)]
        [String]$Location
    )

    Import-Module $PSScriptRoot\ProvisionConfig
    
    $Location = $Location.Replace(" ","").ToLower()

    $config = Get-Configuration
    $provisionConfig = Get-ProvisionConfiguration

    # get pool with greatest number of database 'slots' available
    $availableElasticPool = Get-AvailableElasticPool -Location $Location
        
    # if pool is available with vacant slots 
    if ($availableElasticPool)
    {
        return $availableElasticPool
    }
    else
    {
        # find server with greatest number of pool slots available and create a new pool there
        $availableServer = Get-AvailableServer -Location ($Location)
        
        if ($availableServer)
        {
            $newElasticPoolName = ($provisionConfig.ElasticPoolNameStem + `
                                  ($provisionConfig.ServerElasticPoolsMax - $availableServer.AvailablePoolSlots + 1).ToString())

            Write-Verbose "Provisioning elastic pool '$newElasticPoolName' on server '$($availableServer.ServerName)'. "

            # create new elastic pool in the existing server
            $newElasticPool = New-AzureRmSqlElasticPool `
                -ResourceGroupName $wtpUser.ResourceGroupName `
                -ServerName $availableServer.ServerName `
                -ElasticPoolName $newElasticPoolName `
                -Edition $provisionConfig.ElasticPoolEdition `
                -Dtu $provisionConfig.ElasticPoolDtu `
                -DatabaseDtuMax $provisionConfig.ElasticPoolDatabaseDtuMax `
                -DatabaseDtuMin $provisionConfig.ElasticPoolDatabaseDtuMin              

            # add the extended meta data entry in the catalog
            Set-ExtendedElasticPool `
                -Catalog $catalog `
                -ElasticPool $newElasticPool `
                -BufferDatabases 0

            $extendedElasticPool = Get-ExtendedElasticPool `
                                    -Catalog $catalog `
                                    -ServerName $newElasticPool.ServerName `
                                    -ElasticPoolName $newElasticPool.ElasticPoolName

            $extendedElasticPool | Add-Member AvailableSlots $provisionConfig.ElasticPoolDatabasesMax
            
            return $extendedElasticPool

        }
        else
        {
            # no available servers, create a new server

            $secpasswd = ConvertTo-SecureString $config.TenantAdminPassword -AsPlainText -Force
            $serverCred = New-Object PSCredential ($config.TenantAdminUserName, $secpasswd)
                    
            # get count of current tenant servers in current resource group (regardless of location) 
            # recovery servers (which have the same stem) will be in a separate resource group
            $tenantServers = @()
            $tenantServers += Find-AzureRmResource `
                                -ResourceGroupNameEquals $wtpUser.ResourceGroupName `
                                -ResourceType "Microsoft.Sql/servers" `
                                -ResourceNameContains $provisionConfig.ServerNameStem
            
            # form the next server name
            $nextServerName = $provisionConfig.ServerNameStem + "$($tenantServers.Count + 1)" + "-" + $wtpUser.name

            Write-Verbose "Provisioning tenant server '$nextServerName'. "

            # create a new tenant server 
            $newServer = New-AzureRmSqlServer `
                -ResourceGroupName $wtpUser.ResourceGroupName `
                -Location  $Location `
                -ServerName $nextServerName `
                -SqlAdministratorCredentials $serverCred `
            
            # form elastic pool name
            $elasticPoolName = $provisionConfig.ElasticPoolNameStem + '1'

            Write-Verbose "Provisioning elastic pool '$elasticPoolName' on server '$($newServer.ServerName)'. "

            # create the initial elastic pool in the server
            $newElasticPool = New-AzureRmSqlElasticPool `
                -ResourceGroupName $wtpUser.ResourceGroupName `
                -ServerName $newServer.ServerName `
                -ElasticPoolName $elasticPoolName `
                -Edition $provisionConfig.ElasticPoolEdition `
                -Dtu $provisionConfig.ElasticPoolDtu `
                -DatabaseDtuMax $provisionConfig.ElasticPoolDatabaseDtuMax `
                -DatabaseDtuMin $provisionConfig.ElasticPoolDatabaseDtuMin                

            # add the extended meta data entries for server and pool to the catalog
            
            Set-ExtendedServer `
                -Catalog $catalog `
                -Server $newServer
            
            Set-ExtendedElasticPool `
                -Catalog $catalog `
                -ElasticPool $newElasticPool `
                -BufferDatabases 0
                
            $extendedElasticPool = Get-ExtendedElasticPool `
                                    -Catalog $catalog `
                                    -ServerName $newElasticPool.ServerName `
                                    -ElasticPoolName $newElasticPool.ElasticPoolName

            $extendedElasticPool | Add-Member AvailableSlots $provisionConfig.ElasticPoolDatabasesMax
            
            return $extendedElasticPool
        } 
    }            
}


## -----------------------------------------------------------------------------------

# Initialize the resource id of the source 'golden' database used to create new buffer databases
$subscriptionIdContext = Get-SubscriptionId
$SourceDatabaseId = "/subscriptions/$($subscriptionIdContext)/resourcegroups/$($wtpUser.ResourceGroupName)/providers/Microsoft.Sql/servers/$($config.CatalogServerNameStem + $WtpUser.Name)/databases/$($config.GoldenTenantDatabaseName)"

Write-Output "Checking for buffer database replenishment at $interval second intervals..."

# start the web job continuous execution loop.  The web job sleeps between each iteration.  
# Job is stateless across loops - all resource state is re-acquired in each loop.

While (1 -eq 1)
{
    $loopStart = (Get-Date).ToUniversalTime()

    # Extension Point: to support multiple regions extend here to iterate over each desired region   

    # Check if buffer databases need replenishing in this region  
    
    # get current buffer databases in the region from ARM
    $bufferDatabases = @()
    $bufferDatabases += Find-AzureRmResource `
                        -ResourceGroupNameEquals $wtpUser.ResourceGroupName `
                        -ResourceNameContains $provisionConfig.BufferDatabaseNameStem `
                        -ResourceType Microsoft.Sql/servers/databases `
                        -ODataQuery "Location eq '$($location)'"   

    if ($bufferDatabases.Count -lt $provisionConfig.BufferDatabases)
    {
        # replenish stock of buffer databases by provisioning in batches per the pool, targeting the pool with most space each time.

        $bufferDatabasesNeeded = $provisionConfig.BufferDatabases - $bufferDatabases.Count

        $targetElasticPools = @()

        while ($bufferDatabasesNeeded -gt 0)
        {                
            # Get  pool with the most space.  If no pools have space this function   
            # creates a pool or server + pool as needed. 
    
            $targetElasticPool = Get-TargetElasticPool -Location $location -Verbose

            if ($targetElasticPool.AvailableSlots -le 0)
            {
                throw "No available slots available on target pool.  Check configuration."
            }

            # include this pool in list of pools being updated
            $targetElasticPools += $targetElasticPool
            
            # set the number of available slots in this pool
            $availableSlots = $targetElasticPool.AvailableSlots

            #reset database, server and pool names for the batch 
            $bufferDatabaseNames = @() 
            $serverNames = @()
            $elasticPoolNames = @() 

            while ($availableSlots -gt 0 -and $bufferDatabasesNeeded -gt 0)
            {
                # form the next buffer database name 
                $nextBufferDatabaseName = $provisionConfig.BufferDatabaseNameStem + (New-Guid)

                # add the database name, server name and pool name used for this database into the batch being created 
                $bufferDatabaseNames += $nextBufferDatabaseName
                $serverNames += $targetElasticPool.ServerName
                $elasticPoolNames += $targetElasticPool.ElasticPoolName
                
                # decrement the slots remaining in the pool and the number of buffer databases to be created
                $availableSlots = $availableSlots - 1
                $bufferDatabasesNeeded = $bufferDatabasesNeeded -1 

                if($availableSlots -eq 0 -or $bufferDatabasesNeeded -eq 0)
                { 
                    # Deploy the batch of databases to this pool by copying a 'golden' tenant database from the catalog server.  
                    $deployment = New-AzureRmResourceGroupDeployment `
                        -TemplateFile ($PSScriptRoot + "\Common\" + $config.TenantDatabaseCopyBatchTemplate) `
                        -Location $Location `
                        -ResourceGroupName $wtpUser.ResourceGroupName `
                        -SourceDatabaseId $sourceDatabaseId `
                        -ElasticPoolNames $elasticPoolNames `
                        -ServerNames $serverNames `
                        -DatabaseNames $bufferDatabaseNames `
                        -ErrorAction Stop `
                        -Verbose
                }
            }
        }
        
        # Update the elastic pool entries in the catalog with the latest count of buffer databases
        
        $targetElasticPools = $targetElasticPools | select -Unique

        foreach ($targetElasticPool in $targetElasticPools)
        {
            # get the current set of buffer databases in the pool
            $bufferDatabases = @()
            $bufferDatabases += Get-AzureRmSqlElasticPoolDatabase `
                                    -ResourceGroupName $wtpUser.ResourceGroupName `
                                    -ServerName $targetElasticPool.ServerName `
                                    -ElasticPoolName $targetElasticPool.ElasticPoolName
            $bufferDatabases = $bufferDatabases | select | where DatabaseName -Match "$($provisionConfig.BufferDatabaseNameStem)*" 

            # update the elastic pool entry with the revised buffer database count 
            Set-ExtendedElasticPool `
                -Catalog $catalog `
                -ElasticPool $targetElasticPool `
                -BufferDatabases $bufferDatabases.Count
         }
    }
    
        
    $duration =  [math]::Round(((Get-Date).ToUniversalTime() - $loopStart).Seconds)    
    if ($duration -lt $interval)
    { 
        Write-Verbose "Sleeping for $($interval - $duration) seconds" -Verbose
        Start-Sleep ($interval - $duration)
    }
}
