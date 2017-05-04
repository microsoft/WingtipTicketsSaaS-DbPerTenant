<#
.SYNOPSIS
  Learn how to recover tenant data that has been corrupted. 
  This script deletes the original tenant database and creates a restored database instance with the original name.
  This script assumes that the application is using a database per tenant model.  

.DESCRIPTION
  This script showcases how to recover a tenant database that has had data deleted or corrupted for some reason.

.PARAMETER WtpResourceGroupName
  The name of the Azure resource group that contains the Wingtip Tickets Platform app

.PARAMETER WtpUser
  The 'User' value that was provided during the deployment of the Wingtip Tickets Platform app

.PARAMETER TenantName
  The name of the tenant that owns the database that will be recovered

.PARAMETER RestorePoint
  The point in time in UTC, as a DateTime object, to which the tenant database will be restored

.EXAMPLE
  [PS] C:\>.\Restore-TenantInPlace.ps1 -WtpResourceGroupName "Wingtip-user1" -WtpUser "user1" -TenantName <TenantName> -RestorePoint <UTCDate>
#>
[cmdletbinding()]
param (
    [parameter(Mandatory=$true)]
    [string]$WtpResourceGroupName,

    [parameter(Mandatory=$true)]
    [string]$WtpUser,

    [parameter(Mandatory=$true)]
    [string]$TenantName,

    [parameter(Mandatory=$true)]
    [DateTime]$RestorePoint
)

#----------------------------------------------------------[Initializations]----------------------------------------------------------

# Stop execution on error 
$ErrorActionPreference = "Stop"

Import-Module $PSScriptRoot\..\..\Common\CatalogAndDatabaseManagement -Force
Import-Module $PSScriptRoot\..\..\Common\SubscriptionManagement -Force

# Get Azure credentials if not already logged on
Initialize-Subscription 

#-----------------------------------------------------------[Main Script]------------------------------------------------------------

# Get the catalog
$catalog = Get-Catalog -ResourceGroupName $WtpResourceGroupName -WtpUser $WtpUser

# Compute the key value for the tenant to be restored
$tenantKey = Get-TenantKey $TenantName

# Exit script if tenant does not exist in the catalog 
if (!(Test-TenantKeyInCatalog -Catalog $catalog -TenantKey $tenantKey))
{
    throw "Tenant '$TenantName' does not exist in the catalog. Exiting..."
}

# Mark tenant as offline to prevent access while restore is in progress
Write-Output "Setting tenant '$TenantName' offline in the catalog."

Set-TenantOffline -Catalog $catalog -TenantKey $tenantKey

# Get tenant database that was active during the restore point period 
$restoreSourceDatabase = Get-TenantDatabaseForRestorePoint -Catalog $catalog -TenantKey $tenantKey -RestorePoint $RestorePoint

# Add timestamp to current database name to create name for restored database instance 
$restoreDestinationName = (Get-NormalizedTenantName $TenantName) + $([DateTime]::UtcNow).ToString('yyyy-MM-ddTHH-mm-ssZ')

Write-Output "Restoring from backup of active database at $RestorePoint to create new active database '$restoreDestinationName' ..."

# Restore from deleted tenant database into an elastic pool if the source is an elastic database 
if ($restoreSourceDatabase.DeletionDate -and $restoreSourceDatabase.ElasticPoolName)
{
  $deletionDate = ($restoreSourceDatabase.DeletionDate).ToUniversalTime()
  $restoredTenantDatabase = Restore-AzureRmSqlDatabase -FromDeletedDatabaseBackup `
                              -DeletionDate $deletionDate `
                              -PointInTime $RestorePoint `
                              -ResourceGroupName $WtpResourceGroupName `
                              -ServerName $restoreSourceDatabase.ServerName `
                              -TargetDatabaseName $restoreDestinationName `
                              -ResourceId $restoreSourceDatabase.ResourceID `
                              -ElasticPoolName $restoreSourceDatabase.ElasticPoolName
}
# Restore from deleted tenant database into a standalone database if the source is not an elastic database 
elseif (($restoreSourceDatabase.DeletionDate) -and (!$restoreSourceDatabase.ElasticPoolName))
{
  $deletionDate = ($restoreSourceDatabase.DeletionDate).ToUniversalTime()
  $restoredTenantDatabase = Restore-AzureRmSqlDatabase -FromDeletedDatabaseBackup `
                              -DeletionDate $deletionDate `
                              -PointInTime $RestorePoint `
                              -ResourceGroupName $WtpResourceGroupName `
                              -ServerName $restoreSourceDatabase.ServerName `
                              -TargetDatabaseName $restoreDestinationName `
                              -ResourceId $restoreSourceDatabase.ResourceID `
                              -Edition $restoreSourceDatabase.Edition `
                              -ServiceObjectiveName $restoreSource.CurrentServiceObjectiveName
}
# Restore from active tenant database into an elastic pool if the source is an elastic database 
elseif ((!$restoreSourceDatabase.DeletionDate) -and ($restoreSourceDatabase.ElasticPoolName))
{ 
  $restoredTenantDatabase = Restore-AzureRmSqlDatabase -FromPointInTimeBackup `
                              -PointInTime $RestorePoint `
                              -ResourceGroupName $WtpResourceGroupName `
                              -ServerName $restoreSourceDatabase.ServerName `
                              -TargetDatabaseName $restoreDestinationName `
                              -ResourceId $restoreSourceDatabase.ResourceID `
                              -ElasticPoolName $restoreSourceDatabase.ElasticPoolName
}
# Restore from active tenant database into a standalone database if the source is not an elastic database 
elseif ((!$restoreSourceDatabase.DeletionDate) -and (!$restoreSourceDatabase.ElasticPoolName))
{
  $restoredTenantDatabase = Restore-AzureRmSqlDatabase -FromPointInTimeBackup `
                              -PointInTime $RestorePoint `
                              -ResourceGroupName $WtpResourceGroupName `
                              -ServerName $restoreSourceDatabase.ServerName `
                              -TargetDatabaseName $restoreDestinationName `
                              -ResourceId $restoreSourceDatabase.ResourceID `
                              -Edition $restoreSourceDatabase.Edition `
                              -ServiceObjectiveName $restoreSource.CurrentServiceObjectiveName
}

Write-Output "Deleting active database for $TenantName ..."

# Delete the active tenant database leaving the tenant mapping in the Catalog 
Remove-TenantDatabaseForRestore -Catalog $catalog -TenantKey $tenantKey

$activeTenantDatabaseName = (Get-NormalizedTenantName $TenantName)

# Rename restored tenant database to original instance
Write-Output "Renaming restored tenant database to '$activeTenantDatabaseName' ..."

Rename-TenantDatabase -Catalog $catalog -TenantKey $tenantKey -TargetDatabaseName $activeTenantDatabaseName -TenantDatabaseObject $restoredTenantDatabase

# Mark tenant online to complete the restore process 
Write-Output "Setting tenant '$TenantName' online in the catalog..."

Set-TenantOnline -Catalog $catalog -TenantKey $tenantKey

Write-Output "Restore complete for tenant '$TenantName'."