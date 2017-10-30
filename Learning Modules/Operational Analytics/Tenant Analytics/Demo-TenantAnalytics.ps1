# Helper script for demonstrating tenant analytics using a SQL Database 

Import-Module "$PSScriptRoot\..\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\..\UserConfig" -Force
Import-Module "$PSScriptRoot\..\..\WtpConfig" -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription -NoEcho

# Get the resource group and user names used when the WTP application was deployed from UserConfig.psm1.  
$wtpUser = Get-UserConfig
$config = Get-Configuration

$DemoScenario = 6
<# Select the demo scenario that will be run. It is recommended you run the scenarios below in order. 
     Demo   Scenario
      0       None
      1       Purchase tickets for events at all venues
      2       Deploy tenant analytics database
      3       Deploy tenant analytics columnstore database (creates a Premium P1 database)
      4       Deploy job account and job account database to manage the data extract jobs
      5       Create and run job to extract tenant data to a database for analysis
      6       Create and run job to extract tenant data to a columnstore database for analysis
#>

## ------------------------------------------------------------------------------------------------

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

### Provision a database for operational analytics results
if ($DemoScenario -eq 2)
{
    & $PSScriptRoot\Deploy-TenantAnalyticsDB.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -WtpUser $wtpUser.Name
    exit
}

### Provision a columnstore database for operational tenant analytics results
if ($DemoScenario -eq 3)
{
    & $PSScriptRoot\Deploy-TenantAnalyticsDB-CS.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -WtpUser $wtpUser.Name
    exit
}

### Deploy job account and job account database to manage the data extract jobs
if ($DemoScenario -eq 4)
{
    & "$PSScriptRoot\..\..\Schema Management\Deploy-JobAccount.ps1" `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -WtpUser $wtpUser.Name
    exit
}

### Create and run job to extract tenant data to database for analysis
if ($DemoScenario -eq 5)
{
    $outputServer = $config.catalogServerNameStem + $wtpUser.Name + ".database.windows.net"
    & $PSScriptRoot\Start-TicketDataExtractJob.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -WtpUser $wtpUser.Name `
        -JobExecutionCredentialName $config.JobAccountCredentialName `
        -TargetGroupName "TenantGroup" `
        -OutputServer $outputServer `
        -OutputDatabase $config.TenantAnalyticsDatabaseName `
        -OutputServerCredentialName $config.JobAccountCredentialName `
        -JobName "Extract all tenants ticket purchases to database"
    exit
}

### Create and run job to extract tenant data to columnstore database for analysis
if ($DemoScenario -eq 6)
{
    $outputServer = $config.catalogServerNameStem + $wtpUser.Name + ".database.windows.net"
    & $PSScriptRoot\Start-TicketDataExtractJob.ps1 `
        -WtpResourceGroupName $wtpUser.ResourceGroupName `
        -WtpUser $wtpUser.Name `
        -JobExecutionCredentialName $config.JobAccountCredentialName `
        -TargetGroupName "TenantGroup-CS" `
        -OutputServer $outputServer `
        -OutputDatabase $config.TenantAnalyticsCSDatabaseName `
        -OutputServerCredentialName $config.JobAccountCredentialName `
        -JobName "Extract all tenants ticket purchases to columnstore database"
    exit
}

Write-Output "Invalid scenario selected"
