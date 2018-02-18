# Helper script for deploying and using adhoc reporting

$DemoScenario = 2
<# Select the demo scenario that will be run.
   Scenario
      1       Purchase tickets for events at all venues
      2       Deploy Ad-hoc reporting database 
#>

## ------------------------------------------------------------------------------------------------

Import-Module "$PSScriptRoot\..\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\..\UserConfig" -Force

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

### Purchase new tickets 
if ($DemoScenario -eq 1)
{
    Write-Output "Running ticket generator ..."

    & $PSScriptRoot\..\..\Utilities\TicketGenerator2.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -WtpUser $wtpUser.Name
    exit
}

### Deploy the Ad-hoc Reporting database used with Elastic Query to the catalog server
if ($DemoScenario -eq 2)
{
    & $PSScriptRoot\Deploy-AdhocReportingDB.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -WtpUser $wtpUser.Name
    exit
}


Write-Output "Invalid scenario selected"
