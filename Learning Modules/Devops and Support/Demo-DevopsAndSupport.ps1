# Find tenants by name, then open the selected tenant's database in the Azure Portal  
# Start a load on the databases first with scenario 1 and let it run for a few minutes 
# to make the exploration more interesting.

# Duration of the load generation session. Some activity may continue after this time. 
$DurationMinutes = 60

# This specifies a tenant database to be overloaded in scenario 1. If set to "" a random tenant database is chosen.
$SingleTenantDatabaseName = "fabrikamjazzclub"

# In scenario 1, try entering 'jazz' when prompted to quickly locate Fabrikam Jazz Club. 

$DemoScenario = 1
<# Select the demo scenario to run
    Demo    Scenario
      0       None
      1       Generate a high intensity load (approx 95 DTU) on a single tenant plas a normal intensity load (40 DTU) on all other tenants 
      2       Open a specific tenant's database in the portal plus their public events page
#>

## ------------------------------------------------------------------------------------------------

Import-Module "$PSScriptRoot\..\Common\CatalogAndDatabaseManagement" -Force
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


### Generate a high intensity load (approx 95 DTU) on a single tenant plas a normal intensity load (40 DTU) on all other tenants
if ($DemoScenario -eq 1)
{       
    # First, stop and remove any prior running jobs
    Write-Output "Stopping any prior jobs. This can take a minute or more... "
    Remove-Job * -Force

    # Intensity of normal load, roughly approximates to average eDTU loading on the pool 
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


### Open a specific tenant's database in the portal, plus their public events page
if ($DemoScenario -eq 2)
{       
    $catalog = Get-Catalog `
        -ResourceGroupName $wtpUser.ResourceGroupName `
        -WtpUser $wtpUser.Name

    $tenantNames = @()

    # Get search string from console and find matching tenants
    do 
    {
        [string]$searchString = Read-Host "`nTenant name search string" -ErrorAction Stop       

        Write-Output "`nLooking for tenants..."

        # Check search string is valid and prevent SQL injection
        Test-LegalNameFragment $searchString

        # Find tenants with names that match the search string
        $tenantNames += Find-TenantNames -Catalog $catalog -SearchString $searchString

        if(-not $tenantNames)
        {
            Write-Output "No tenants found matching '$searchString', try again or ctrl-c to exit" 
        }

    } while (-not $tenantNames)

    # Display matching tenants 
    $index = 1
    foreach($tenantName in $TenantNames)
    {
        $tenantName | Add-Member -type NoteProperty -name "Tenant" -value $index
        $index++
    }

    # Prompt for selection 
    Write-Output "Matching tenants: "
    $TenantNames | Format-Table Tenant,TenantName -AutoSize
            
    # Get the tenant selection from console and open database in portal and the corresponding events page  
    do
    {
        try
        {
            [int]$selectedRow = Read-Host "`nEnter the tenant number to open database in portal, 0 to exit" -ErrorAction Stop

            if ($selectedRow -ne 0)
            {
                $selectedTenantName = $TenantNames[$selectedRow - 1].TenantName

                # Open the events page for the new venue to verify it's working correctly
                Start-Process "http://events.wtp.$($wtpUser.Name).trafficmanager.net/$(Get-NormalizedTenantName $selectedTenantName)"

                # open the database blade in the portal to review performance
                Open-TenantResourcesInPortal `
                    -Catalog $catalog `
                    -TenantName $selectedTenantName `
                    -ResourceTypes ('database')  
            }
            exit       
        }
        catch
        { 
            Write-Output 'Invalid selection.'         
        }

    } while (1 -eq 1)

    exit
}

Write-Output "Invalid scenario selected"