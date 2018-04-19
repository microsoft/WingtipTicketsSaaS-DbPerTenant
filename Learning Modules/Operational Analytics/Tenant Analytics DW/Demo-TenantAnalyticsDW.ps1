# Helper script for exploring tenant analytics using a SQL Data Warehouse

Import-Module "$PSScriptRoot\..\..\Common\SubscriptionManagement" -Force
Import-Module $PSScriptRoot\..\..\Common\CatalogAndDatabaseManagement -Force
Import-Module "$PSScriptRoot\..\..\UserConfig" -Force
Import-Module "$PSScriptRoot\..\..\WtpConfig" -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription -NoEcho

$DemoScenario = 0
<# Select the scenario that will be run. It is recommended you run the scenarios below in order. 
   Scenario
      0    None
      1    Purchase tickets for events at all venues (required if not already done in another scenario)
      2    Deploy tenant analytics data warehouse, storage account and data factory 
#>

## ------------------------------------------------------------------------------------------------

### Default state - enter a valid scenaro 
if ($DemoScenario -eq 0)
{
    Write-Output "Please modify the demo script to select a scenario to run."
    exit
}

# Get the resource group and user names used when the WTP application was deployed from UserConfig.psm1.  
$wtpUser = Get-UserConfig
$config = Get-Configuration

### Purchase tickets for events at all venues 
if ($DemoScenario -eq 1)
{
    Write-Output "Starting ticket generator ..."

    & $PSScriptRoot\..\..\Utilities\TicketGenerator2.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -WtpUser $wtpUser.Name
    exit
}

### Deploy tenant analytics data warehouse, storage account and data factory
if ($DemoScenario -eq 2)
{
    & $PSScriptRoot\Deploy-TenantAnalyticsDW.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -WtpUser $wtpUser.Name
    exit
}

Write-Output "Invalid scenario selected"
