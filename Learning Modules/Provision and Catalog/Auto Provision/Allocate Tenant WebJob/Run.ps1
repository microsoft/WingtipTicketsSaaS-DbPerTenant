# WebJob that allocates pre-created tenant databases to new tenants in response to tenant requests.

# IMPORTANT: The Service Principal used MUST have been created previously for this app in Active Directory 
# and given reader rights to resources in the WTP resource group.  See Deploy-CatalogSync.ps1

# Provide values for the following before deploying:
 
    #> Active Directory domain (see Azure portal, displayed in top right corner, typically in format "<...>.onmicrosoft.com")
    $domainName = "<domainName>"

    #> Azure Tenant Id
    $tenantId = "<tenantId>"

    #> Azure subscription ID for the subscription under which the WTP app is deployed 
    $subscriptionId = "<subscriptionId>"

    # Check for tenant requests every 10 seconds.   
    $interval = 10

Import-Module $PSScriptRoot\Common\CatalogAndDatabaseManagement -Force
Import-Module $PSScriptRoot\WtpConfig -Force
Import-Module $PSScriptRoot\ProvisionConfig -Force
Import-Module $PSScriptRoot\UserConfig -Force

# Get the resource group and user names used when the WTP application was deployed from UserConfig.psm1.  
$wtpUser = Get-UserConfig

# Get application configuration
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

# Get the catalog 
$catalog = Get-Catalog -ResourceGroupName $WtpUser.ResourceGroupName -WtpUser $WtpUser.Name

## ---------------------------------------------------------------------------------------

Write-Output "Checking for new tenant requests at $interval second intervals..."

# start the web job continuous execution loop.  The web job sleeps between each iteration.
# Job is stateless across loops - all resource state is re-acquired in each loop.  

While (1 -eq 1)
{
    $loopStart = (Get-Date).ToUniversalTime()

    # get new tenant requests to be processed
    
    $commandText = "
        SELECT TenantName, VenueType, ServicePlan, PostalCode, CountryCode, Location FROM [dbo].[TenantRequests]
        WHERE RequestState = 'submitted'"
    $requests = @()
    $requests += Invoke-SqlAzureWithRetry `
                    -ServerInstance $Catalog.FullyQualifiedServerName `
                    -Username $config.CatalogAdminUserName `
                    -Password $config.CatalogAdminPassword `
                    -Database $catalog.Database.DatabaseName `
                    -Query $commandText
                    
    if ($requests.Count -gt 0)
    {        

        # get available buffer databases in the requested region
        $bufferDatabases = Find-AzureRmResource `
                            -ResourceGroupNameEquals $wtpUser.ResourceGroupName `
                            -ResourceNameContains $provisionConfig.BufferDatabaseNameStem `
                            -ResourceType Microsoft.Sql/servers/databases `
                            -ODataQuery "Location eq '$($requests[0].Location)'"
        
        if ($bufferDatabases)
        {                       
            # convert to a collection to allow removal of items
            $bufferDatabases = {$bufferDatabases}.Invoke() 
            
            foreach($request in $requests)
            {
                # verify requested tenant is not already registered in catalog
                $tenantKey = Get-TenantKey -TenantName $request.TenantName
                if (Test-TenantKeyInCatalog -Catalog $catalog -TenantKey $tenantKey)
                {
                    write-output "Tenant '$($request.TenantName)' is already registered" 
                    continue
                }

                # get a buffer database and allocate it to the requesting tenant
                $nextBufferDatabase = $bufferDatabases | select-object -first 1

                Initialize-TenantFromBufferDatabase `
                    -Catalog $catalog `
                    -TenantName $request.TenantName `
                    -VenueType $request.VenueType `
                    -PostalCode $request.PostalCode `
                    -CountryCode $request.CountryCode `
                    -BufferDatabase $nextBufferDatabase `
                    -ErrorAction Stop `
                    > $null

                # and remove the buffer database from set of available databases this iteration
                $bufferDatabases.Remove($nextBufferDatabase) > $null

                # update new tenant request to indicate tenant has been successfully allocated
                $commandText = "
                    UPDATE [dbo].[TenantRequests]
                    SET RequestState = 'allocated', LastUpdated = CURRENT_TIMESTAMP
                    WHERE TenantName = '$($request.TenantName)' AND RequestState = 'submitted'"

                Invoke-SqlAzureWithRetry `
                    -ServerInstance $Catalog.FullyQualifiedServerName `
                    -Username $config.CatalogAdminUserName `
                    -Password $config.CatalogAdminPassword `
                    -Database $catalog.Database.DatabaseName `
                    -Query $commandText
            }
        }        
        else
        {
            # buffer databases are not available for allocation, will try again on next iteration
            write-output "No buffer databases available in $($request.Location) at $((Get-Date).ToUniversalTime())"                                           
        }
    }

    $duration =  [math]::Round(((Get-Date).ToUniversalTime() - $loopStart).Seconds)    
    if ($duration -lt $interval)
    { 
        #Write-Verbose "Sleeping for $($interval - $duration) seconds" -Verbose
        Start-Sleep ($interval - $duration)
    }
}
