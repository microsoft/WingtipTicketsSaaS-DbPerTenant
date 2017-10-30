<#
.SYNOPSIS
  Resets the event dates in all tenant databases registered in the catalog   

.DESCRIPTION
  Resets the event dates in all tenant databases registered in the catalog.  Calls sp_ResetEventDates
  in each database. Two events are set in the recent past, the remainder are rescheduled into the future.  

#>
param(
    [Parameter(Mandatory=$true)]
    [string]$WtpResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$WtpUser
)

Import-Module $PSScriptRoot\..\Common\CatalogAndDatabaseManagement -Force

$config = Get-Configuration

# Get the catalog 
$catalog = Get-Catalog -ResourceGroupName $WtpResourceGroupName -WtpUser $WtpUser 

$databaseLocations = Get-TenantDatabaseLocations -Catalog $catalog

$commandText = "EXEC sp_ResetEventDates"

foreach ($dbLocation in $databaseLocations)
{ 
    Write-Output "Resetting event dates for '$($dblocation.Location.Database)'."
    Invoke-Sqlcmd `
        -ServerInstance $($dbLocation.Location.Server) `
        -Username $($config.TenantAdminuserName) `
        -Password $($config.TenantAdminPassword) `
        -Database $($dblocation.Location.Database) `
        -Query $commandText `
        -ConnectionTimeout 30 `
        -QueryTimeout 30 `
        -EncryptConnection

}