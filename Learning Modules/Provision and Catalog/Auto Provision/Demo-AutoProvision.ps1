# Demo script for enabling auto-provisioning.  Deploys the catalog management app service and creates its service principal. 
# This app service hosts the web jobs that provide automated catalog management functions, which must be manually deployed. 

$DemoScenario = 1
<# Select the demo scenario that will be run. 
     Demo   Scenario
      0       None
      1       Deploy the Catalog Management App Service and create its service principal in AAD
      2       Display Tenant Id and Subscription Id - required to initialize the web jobs
      3       Submit a request to provision a single tenant
      4       Submit a batch of tenant provisioning requests  
#>

## ------------------------------------------------------------------------------------------------

#Import-Module "$PSScriptRoot\..\Common\CatalogAndDatabaseManagement" -Force
Import-Module "$PSScriptRoot\..\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\..\WtpConfig" -Force
Import-Module "$PSScriptRoot\..\..\UserConfig" -Force

# Get Azure credentials if not logged on. Use -Force to login again and optionally select a different subscription 
Initialize-Subscription #-NoEcho

# Get the resource group and user names used when the WTP application was deployed from UserConfig.psm1  
$wtpUser = Get-UserConfig

# Get the WTP configuration
$config = Get-Configuration

# get the Azure Context to retrieve subscription ID
$azureContext = Get-AzureRmContext
$subscriptionId = $azureContext.Subscription.SubscriptionId

### Default state - enter a valid demo scenaro 
if ($DemoScenario -eq 0)
{
  Write-Output "Please modify the demo script to select a scenario to run."
  exit
}

### Deploy the Catalog Management App Service   
if ($DemoScenario -eq 1)
{
    # Construct the application display name
    $applicationName = $config.CatalogManagementAppNameStem + $wtpUser.Name

    # Create server principal under the current subscription, with contributor rights scoped to the WTP resource group 
    & $PSScriptRoot\Add-ServicePrincipalWithPassword `
        -ResourceGroup $wtpUser.ResourceGroupName `
        -ApplicationName $applicationName `
        -Password $config.ServicePrincipalPassword `
        -RbacRole "contributor"
    
    # get the resource group used during deployment to get the location being used for the WTP apps
    $wtpResourceGroup = Get-AzureRmResourceGroup -Name $wtpUser.ResourceGroupName

    # Deploy the app service that will host the web job using an ARM template (sets to Always On) 
    $deployment = New-AzureRmResourceGroupDeployment `
        -TemplateFile "$PSScriptRoot\..\..\Common\$($config.WebApplicationTemplate)" `
        -Location $wtpResourceGroup.Location `
        -ResourceGroupName $wtpUser.ResourceGroupName `
        -AppName $applicationName `
        -HostingPlanName $applicationName `
        -WorkerSize $config.CatalogManagementAppWorkerSize `
        -ServerFarmResourceGroup $wtpUser.ResourceGroupName `
        -Sku $config.CatalogManagementAppSku `
        -SkuCode $config.CatalogManagementAppSkuCode `
        -SubscriptionId $SubscriptionId `
        -ErrorAction Stop `
        -Verbose     

    Write-Output "App Service '$applicationName' deployed"
  
    exit
}


### Display Tenant Id and Subscription Id  
if ($DemoScenario -eq 2)
{
  Write-Output "Tenant ID: $($azureContext.Tenant.TenantId)"
  Write-Output "Subscription Id: $($azureContext.Subscription.SubscriptionId) "
  
  exit
}

### Submit a request to provision a single tenant
if ($DemoScenario -eq 3)
{
    # Get the location (Azure region) in which the tenant will be provisioned.  
    # Currently only supports provisioning in the region in which the app was initially deployed.
    $location = (Get-AzureRmResourceGroup -Name $wtpUser.ResourceGroupName).Location

     & $PSScriptRoot\New-TenantRequest.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -WtpUser $wtpUser.Name `
        -TenantName $TenantName `
        -VenueType $VenueType `
        -Location $location        

    exit
}

### Submit a batch of tenant provisioning requests
if ($DemoScenario -eq 4)
{
    $config = Get-Configuration

    # the batch of venue names and corresponding venue type is pre-defined in  configuration
    $tenantNames = $config.TenantNameBatch

    # Get the location (Azure region) in which the tenants will be provisioned.  
    # Currently only supports provisioning in the region in which the app was initially deployed.
    $location = (Get-AzureRmResourceGroup -Name $wtpUser.ResourceGroupName).Location

    & $PSScriptRoot\New-TenantRequestBatch.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -WtpUser $wtpUser.Name `
        -NewTenants $tenantNames `
        -Location $location 
    
    exit
}

Write-Output "Invalid scenario selected"