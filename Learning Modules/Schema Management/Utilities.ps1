# Useful script fragments for managing job accounts.  Not you cannot delete a job account database
# without first deleting the jJob Account that references it.  Uncomment the cmdlets you wish to run.
# Execute with F5 to ensure $PSScriptRoot is evaluated.

Import-Module "$PSScriptRoot\..\WtpConfig" -Force
Import-Module "$PSScriptRoot\..\UserConfig" -Force

# Get the resource group and user value used when the Wingtip SaaS application was deployed from UserConfig.psm1.  
$wtpUser = Get-UserConfig
$config = Get-Configuration

$serverName = $config.CatalogServerNameStem + $wtpUser.Name
$resourceGroupName = $wtpUser.ResourceGroupName

<#
Remove-AzureRmSqlJobAccount `
-ServerName $serverName `
-JobAccountName $($config.JobAgent) `
-ResourceGroupName $resourceGroupName
#>

<#
Get-AzureRmSqlJobAccount `
-ServerName $serverName `
-JobAccountName $($config.JobAgent) `
-ResourceGroupName $resourceGroupName 
#>

<#
New-AzureRmSqlJobAccount `
-ServerName $serverName `
-JobAccountName $($config.JobAgent) `
-ResourceGroupName $resourceGroupName `
-DatabaseName $($config.JobAgentDatabaseName)
#>
