<#
.SYNOPSIS
  Restores a tenant's database from an earlier point in time into a parallel tenant database with a new catalog entry named <tenantName>_old 

.DESCRIPTION
  Restores a tenant's database from an earlier point in time into a parallel tenant database with a new catalog entry named <tenantName>_old.
  Any prior restored database will be deleted.  Use this script to allow a tenant to examine a prior state of their data to 
  aid in recovery from a accidental corruption or for compliance or audit purposes.   

.PARAMETER WtpResourceGroupName
  The name of the Azure resource group used during the deployment of the Wingtip Tickets Platform app 

.PARAMETER WtpUser
  The 'User' value that was provided during the deployment of the Wingtip Tickets Platform app

.PARAMETER TenantName
  The name of the tenant that owns the database that will be recovered

.PARAMETER RestorePoint
  The point in time in UTC, as a DateTime object, to which the new tenant database will be restored.

.EXAMPLE
  [PS] C:\>.\Restore-TenantInParallel.ps1 -WtpResourceGroupName "Wingtip-user1" -WtpUser "user1" -TenantName <TenantName> -RestorePoint <UTCDate>
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

#----------------------------------------------------------[Initialization]----------------------------------------------------------

# Stop execution on error 
$ErrorActionPreference = "Stop"

Import-Module $PSScriptRoot\..\..\Common\CatalogAndDatabaseManagement -Force
Import-Module $PSScriptRoot\..\..\Common\SubscriptionManagement -Force

# Get Azure credentials if not already logged on
Initialize-Subscription

#-----------------------------------------------------------[Main Script]------------------------------------------------------------

# Get catalog database that contains metadata about all Wingtip tenant databases
$catalog = Get-Catalog -ResourceGroupName $WtpResourceGroupName -WtpUser $WtpUser

# Compute the key value for the tenant to be restored
$tenantKey = Get-TenantKey -TenantName $TenantName

# Exit script if tenant does not exist in the catalog 
if (!(Test-TenantKeyInCatalog -Catalog $catalog -TenantKey $tenantKey))
{
    throw "Tenant '$TenantName' does not exist in the catalog. Exiting ..."
}

# Get tenant database that was active during the restore point period 
$restoreSourceDatabase = Get-TenantDatabaseForRestorePoint -Catalog $catalog -TenantKey $tenantKey -RestorePoint $RestorePoint 

$restoredTenantName = (Get-NormalizedTenantName -TenantName $TenantName) + "_old"
$restoredTenantKey = Get-TenantKey -TenantName $restoredTenantName

# Delete any previously restored tenant database with suffix '_old'
if (Test-TenantKeyInCatalog -Catalog $catalog -TenantKey $restoredTenantKey)
{
  Write-Output "Deleting previous restored tenant database, '$restoredTenantName' ..."
  Remove-Tenant -Catalog $catalog -TenantKey $restoredTenantKey
}

# Restore tenant database from the restore point to its prior service objective or elastic pool 
Write-Output "Restoring from backup of database '$($restoreSourceDatabase.DatabaseName)' at $RestorePoint into '$restoredTenantName' ..."

# Restore from deleted tenant database into an elastic pool if the source is an elastic database 
if ($restoreSourceDatabase.DeletionDate -and $restoreSourceDatabase.ElasticPoolName)
{
  $deletionDate = ($restoreSourceDatabase.DeletionDate).ToUniversalTime()
  $restoredTenantDatabase = Restore-AzureRmSqlDatabase -FromDeletedDatabaseBackup `
                              -DeletionDate $deletionDate `
                              -PointInTime $RestorePoint `
                              -ResourceGroupName $WtpResourceGroupName `
                              -ServerName $restoreSourceDatabase.ServerName `
                              -TargetDatabaseName $restoredTenantName `
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
                              -TargetDatabaseName $restoredTenantName `
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
                              -TargetDatabaseName $restoredTenantName `
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
                              -TargetDatabaseName $restoredTenantName `
                              -ResourceId $restoreSourceDatabase.ResourceID `
                              -Edition $restoreSourceDatabase.Edition `
                              -ServiceObjectiveName $restoreSource.CurrentServiceObjectiveName
}

# Remove old catalog references in the restored tenant database 
Remove-CatalogInfoFromTenantDatabase -TenantKey $restoredTenantKey -TenantDatabase $restoredTenantDatabase -ErrorAction Continue

# Add the restored tenant database to the catalog with <tenantname>_old
Add-TenantDatabaseToCatalog -Catalog $catalog `
    -TenantName ($TenantName + "_old")`
    -TenantKey $restoredTenantKey `
    -TenantDatabase $restoredTenantDatabase

Write-Output "Restored tenant '$restoredTenantName' is available for use."
