# Helper script for demonstrating performance montoring and management tasks.

# Duration of the load generation sessions. Some activity may continue after this time. 
$DurationMinutes = 60

# If the SingleTenant scenario used, this is the tenant database that will have the high load applied, 
# or if set to empty string ("") a random tenant database will be chosen.
$SingleTenantDatabaseName = "contosoconcerthall"

$DemoScenario = 0
<# Select the demo scenario to run 
    Demo    Scenario
      0       None
      1       Provision a batch of tenants (do this before any of the load generation scenarios)
      2       Generate normal intensity load (approx 40 DTU) 
      3       Generate load with longer and more frequent bursts per database
      4       Generate load with higher DTU bursts per database (approx 80 DTU)  
      5       Generate a normal load plus a high load on a single tenant (approx 95 DTU) 
      6       Generate unbalanced load across multiple pools  
#>

## --------------------------------------------------------------------------------------

Import-Module $PSScriptRoot\..\Common\CatalogAndDatabaseManagement -Force
Import-Module "$PSScriptRoot\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\UserConfig" -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription -NoEcho

# Get the resource group and user names used when the WTP application was deployed from UserConfig.psm1.  
$wtpUser = Get-UserConfig

### Default state - enter a valid demo scenaro 
if ($DemoScenario -eq 0)
{
  Write-Output "Please modify the demo script to select a scenario to run."
  exit
}

### Provision a batch of tenants
if ($DemoScenario -eq 1)
{
    $config = Get-Configuration

    $tenantNames = $config.TenantNameBatch

    & "$PSScriptRoot\..\Provision And Catalog\New-TenantBatch.ps1" `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -WtpUser $wtpUser.Name `
        -NewTenants $tenantNames
          
    exit          
}

### Generate normal intensity load
if ($DemoScenario -eq 2)
{       
    # First, stop any prior running jobs
    Write-Output "Stopping any prior jobs. This can take a minute or more... "
    Remove-Job * -Force

    # Intensity of load, roughly approximates to average eDTU loading on the getpool 
    $Intensity = 40   

    # start a new set of load generation jobs for the current databases with the load configuration above
    & $PSScriptRoot\..\Utilities\LoadGenerator.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -Wtpuser $wtpUser.Name `
        -Intensity $Intensity `
        -DurationMinutes $DurationMinutes
                 
    exit
}

### Generate load with longer bursts per database
if ($DemoScenario -eq 3)
{       
    # First, stop any prior running jobs
    Write-Output "Stopping any prior jobs. This can take a minute or more... "
    Remove-Job * -Force

    # Intensity of load, roughly approximates to average eDTU loading on the getpool 
    $Intensity = 40

    # start a new set of load generation jobs for the current databases with the load configuration above
    & $PSScriptRoot\..\Utilities\LoadGenerator.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -Wtpuser $wtpUser.Name `
        -Intensity $Intensity `
        -DurationMinutes $DurationMinutes `
        -LongerBursts  

    exit             
}      

### Generate load with higher DTU bursts per database
if ($DemoScenario -eq 4)
{       
    # First, stop any prior running jobs
    Write-Output "Stopping any prior jobs. This can take a minute or more... "
    Remove-Job * -Force

    # Intensity of load, roughly approximates to average eDTU loading on the getpool 
    $Intensity = 80   

    # start a new set of load generation jobs for the current databases with the load configuration above
    & $PSScriptRoot\..\Utilities\LoadGenerator.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -Wtpuser $wtpUser.Name `
        -Intensity $Intensity `
        -DurationMinutes $DurationMinutes 
        
    exit        
} 

### Generate normal intensity load (approx 40 DTU) plus a high intensity (approx 95 DTU) load on a single tenant
if ($DemoScenario -eq 5)
{       
    # First, stop any prior running jobs
    Write-Output "Stopping any prior jobs. This can take a minute or more... "
    Remove-Job * -Force

    # Intensity of normal load, roughly approximates to average eDTU loading on the getpool 
    $Intensity = 40   

    # Intensity of high load on single tenant
    $SingleTenantDtu = 95

    # start a new set of load generation jobs for the current databases with the load configuration above
    & $PSScriptRoot\..\Utilities\LoadGenerator.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -Wtpuser $wtpUser.Name `
        -Intensity $Intensity `
        -DurationMinutes $DurationMinutes `
        -SingleTenant `
        -SingleTenantDatabaseName $SingleTenantDatabaseName `
        -SingleTenantDtu $SingleTenantDtu
    
    exit         
}

### Generate unbalanced load (either 30 DTU or 60 DTU) across multiple pools 
if ($DemoScenario -eq 6)
{       
    # First, stop any prior running jobs
    Write-Output "Stopping any prior jobs. This can take a minute or more... "
    Remove-Job * -Force

    # Intensity of load, roughly approximates to average eDTU loading on the getpool 
    $Intensity = 40

    # start a new set of load generation jobs for the current databases with the load configuration above
    & $PSScriptRoot\..\Utilities\LoadGenerator.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -Wtpuser $wtpUser.Name `
        -Intensity $Intensity `
        -DurationMinutes $DurationMinutes `
        -Unbalanced 
     
     exit         
}  

Write-Output "Invalid scenario selected"