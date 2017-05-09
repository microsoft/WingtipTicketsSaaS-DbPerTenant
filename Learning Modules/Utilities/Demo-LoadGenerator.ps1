# Invokes load generator script over the tenant databases currently defined in the catalog.  
 
# Duration of the load generation session. Some activity may continue after this time. 
$DurationMinutes = 120

# If SingleTenant is enabled (scenario 4), this specifies the tenant database to be overloaded. 
# If set to "" a random tenant database is chosen.
$SingleTenantDatabaseName = "contosoconcerthall"

$DemoScenario = 1
<# Select the demo scenario to run 
    Demo    Scenario
      0       None
      1       Start a normal intensity load (approx 40 DTU) 
      2       Start a load with longer bursts per database
      3       Start a load with higher DTU bursts per database (approx 80 DTU)  
      4       Start a high intensity load (approx 95 DTU) on a single tenant plas a normal intensity load on all other tenants 
      5       Start an unbalanced load across multiple pools  
#>

## ------------------------------------------------------------------------------------------------

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

### Generate normal intensity load
if ($DemoScenario -eq 1)
{       
    # First, stop and remove any prior running jobs
    Write-Output "`nStopping any prior jobs. This can take a minute or more... "
    Remove-Job * -Force

    # Intensity of load, roughly approximates to average eDTU loading on the pool 
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
if ($DemoScenario -eq 2)
{       
    # First, stop and remove any prior running jobs
    Write-Output "`nStopping any prior jobs. This can take a minute or more... "    
    Remove-Job * -Force

    # Intensity of load, roughly approximates to average eDTU loading on the pool 
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
if ($DemoScenario -eq 3)
{       
    # First, stop and remove any prior running jobs
    Write-Output "`nStopping any prior jobs. This can take a minute or more... "
    Remove-Job * -Force

    # Intensity of load, roughly approximates to average eDTU loading on the pool 
    $Intensity = 80   

    # start a new set of load generation jobs for the current databases with the load configuration above
    & $PSScriptRoot\..\Utilities\LoadGenerator.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -Wtpuser $wtpUser.Name `
        -Intensity $Intensity `
        -DurationMinutes $DurationMinutes 
        
    exit        
} 

### Generate a high intensity load (approx 95 DTU) on a single tenant plas a normal intensity load (40 DTU) on all other tenants
if ($DemoScenario -eq 4)
{       
    # First, stop and remove any prior running jobs
    Write-Output "`nStopping any prior jobs. This can take a minute or more... "
    Remove-Job * -Force

    # Intensity of load, roughly approximates to average eDTU loading on the pool 
    $Intensity = 40   

    # start a new set of load generation jobs for the current databases with the load configuration above
    & $PSScriptRoot\..\Utilities\LoadGenerator.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -Wtpuser $wtpUser.Name `
        -Intensity $Intensity `
        -DurationMinutes $DurationMinutes `
        -SingleTenant `
        -SingleTenantDatabaseName $SingleTenantDatabaseName
    
    exit         
}

### Generate unbalanced load (either 30 DTU or 60 DTU) across multiple pools 
if ($DemoScenario -eq 5)
{       
    # First, stop and remove any prior running jobs
    Write-Output "`nStopping any prior jobs. This can take a minute or more... "
    Remove-Job * -Force

    # Intensity of load, roughly approximates to average eDTU loading on the pool 
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