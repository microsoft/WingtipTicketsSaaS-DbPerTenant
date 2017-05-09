<#
.SYNOPSIS
  Provisions a batch of WTP tenants and registers them in the catalog   

.DESCRIPTION
  Creates a batch of new tenants using an ARM template.  The template uses a linked template, tenantdatabasetemplate,
  for each tenant, which creates a database and imports the WTP tenant bacpac.  Once all databases are deployed they
  are initialized with venue information and registered in the catalog and mapped to a tenant key generated from the 
  tenant name.

.PARAMETER WtpResourceGroupName
  The resource group name used during the deployment of the WTP app (case sensitive)

.PARAMETER WtpUser
  The 'User' value that was entered during the deployment of the WTP app

.PARAMETER NewTenants
  An array of Tenant Names plus Venue Types
#>

Param(
    [Parameter(Mandatory=$true)]
    [string]$WtpResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$WtpUser,

    [Parameter(Mandatory=$true)]
    [string[][]]$NewTenants
)
$start = Get-Date 
$WtpUser = $WtpUser.ToLower()

Import-Module $PSScriptRoot\..\Common\SubscriptionManagement -Force
Import-Module $PSScriptRoot\..\Common\CatalogAndDatabaseManagement -Force
Import-Module $PSScriptRoot\..\WtpConfig -Force

$config = Get-Configuration
$serverName = $config.TenantServerNameStem + $WtpUser 
$fullyQualifiedServerName = $serverName + ".database.windows.net"
$elasticPoolName = $config.TenantPoolNameStem + "1"

## MAIN SCRIPT ## ----------------------------------------------------------------------------

# Ensure logged in to Azure
Initialize-Subscription

# Check the tenant server exists
$Server = Get-AzureRmSqlServer -ResourceGroupName $WtpResourceGroupName -ServerName $serverName 

if (!$Server)
{
    throw "Could not find tenant server '$serverName'."
}

# Get the catalog 
$catalog = Get-Catalog -ResourceGroupName $WtpResourceGroupName -WtpUser $WtpUser

#Configure the batch deployment tenant for all the tenants

[object[]]$allNewTenants = @()
$batchDatabaseNames = @()
$batchserverNames = @()
$batchElasticPoolNames = @()

foreach ($newTenant in $NewTenants)
{
    $newTenantName = $newTenant[0].Trim()
    $newTenantVenueType = $newTenant[1].Trim()
    $newTenantPostalCode = $newTenant[2].Trim()

    try
    {
        Test-LegalName $newTenantName > $null
        Test-LegalVenueTypeName $newTenantVenueType > $null
    }
    catch
    {
        throw
    }
    $normalizedNewTenantName = Get-NormalizedTenantName $newTenantName

    $newTenantObj =  New-Object PSObject -Property @{
        Name = $newTenantName
        NormalizedName = $normalizedNewTenantName
        VenueType = $newTenantVenueType
        PostalCode = $newTenantPostalCode
        }

    $allNewTenants += $newTenantObj

    $tenantKey = Get-TenantKey -TenantName $newTenantName
    
    # Check if a tenant with this key is aleady registered in the catalog
    if (Test-TenantKeyInCatalog -Catalog $catalog -TenantKey $tenantKey)
    {
        Write-Output "Tenant '$newTenantName' is already registered in the catalog.  Skipping database creation..."
        continue    
    }     

    # Check if a database with this name exists
    $existingTenantDatabase = Get-AzureRmSqlDatabase `
        -ResourceGroupName $WtpResourceGroupName `
        -ServerName $serverName `
        -DatabaseName $normalizedNewTenantName `
        -ErrorAction SilentlyContinue

    if ($existingTenantDatabase)
    {
        Write-Output "Database '$normalizedNewTenantName' already exists.  Skipping database creation..."
        continue
    }

    # add database, server and elastic pool names to the batch
    $batchDatabaseNames += $normalizedNewTenantName
    $batchServerNames += $serverName
    $batchElasticPoolNames += $elasticPoolName
} 

if ($batchDatabaseNames.Count -gt 0)
{

    Write-Output "Provisioning $($batchDatabaseNames.Count) databases..." 
    
    try
    {
        # Construct the resource id for the 'golden' tenant database on the catalog server
        $AzureContext = Get-AzureRmContext
        $SourceDatabaseId = "/subscriptions/$($AzureContext.Subscription.SubscriptionId)/resourcegroups/$WtpResourceGroupName/providers/Microsoft.Sql/servers/$($config.CatalogServerNameStem)$WtpUser/databases/$($config.GoldenTenantDatabaseName)"
        
        # Use nested ARM templates to create the tenant database by copying the 'golden' database
        $deployment = New-AzureRmResourceGroupDeployment `
            -TemplateFile ($PSScriptRoot + "\..\Common\" + $config.TenantDatabaseCopyBatchTemplate) `
            -Location $Server.Location `
            -ResourceGroupName $WtpResourceGroupName `
            -SourceDatabaseId $sourceDatabaseId `
            -ServerNames $batchServerNames `
            -DatabaseNames $batchDatabaseNames `
            -ElasticPoolNames $batchElasticPoolNames `
            -ErrorAction Stop `
            -Verbose                 
    }
    catch
    {
        Write-Error "An error occurred during template deployment. One or more databases may not be deployed or have imported the initial schema"
        throw
    }
}

Write-Output "Initializing databases..."

# process all new tenants and (re-)initialize the databases.  Ensures that this occurs for all dbs
# if re-running the script after a partial failure/interruption.    
foreach($tenant in $allNewTenants)
{
    # Database initialization and registration in the catalog is idempotent
            
    # Get the tenant database
    $tenantDatabase = Get-AzureRmSqlDatabase `
        -ResourceGroupName $WtpResourceGroupName `
        -ServerName $serverName `
        -DatabaseName $tenant.NormalizedName

    # Initialize the venue information in the tenant database and reset the default event dates
    Initialize-TenantDatabase `
        -ServerName $serverName `
        -DatabaseName $tenant.NormalizedName `
        -TenantName $tenant.Name `
        -VenueType $tenant.VenueType `
        -PostalCode $tenant.PostalCode

    $tenantKey = Get-TenantKey -TenantName $tenant.Name

    # Register the tenant to database mapping in the catalog
    Add-TenantDatabaseToCatalog -Catalog $catalog `
        -TenantName $tenant.Name `
        -TenantKey $tenantKey `
        -TenantDatabase $tenantDatabase

    Write-Output "Tenant '$($tenant.Name)' initialized and registered in the catalog."
} 


$end = Get-Date

Write-Output "Tenant provisioning complete.  $($batchDatabaseNames.Count) new tenant databases provisioned."
write-output "Duration $(($end - $start).Minutes) minutes $(($end - $start).seconds) seconds"