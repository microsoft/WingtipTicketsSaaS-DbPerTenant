<#
.SYNOPSIS
  Extracts ticket sales data from a tenant database to an analysis database or data warehouse

.DESCRIPTION
  Creates an Elastic Job that extracts ticket sales data from a tenant database and 
  outputs it to an analysis database or data warehouse 
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$WtpResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$WtpUser,

    [Parameter(Mandatory=$true)]
    [string]$JobExecutionCredentialName,

    [Parameter(Mandatory=$true)]
    [string]$OutputServer,

    [Parameter(Mandatory=$true)]
    [string]$OutputDataWarehouse,

    [Parameter(Mandatory=$true)]
    [string]$OutputServerCredentialName,

    [Parameter(Mandatory=$false)]
    [string]$OutputTableName = "AllTicketPurchasesFromAllTenants"
)

Import-Module $PSScriptRoot\..\..\Common\SubscriptionManagement -Force
Import-Module $PSScriptRoot\..\..\WtpConfig -Force


# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription

$config = Get-Configuration

# Get server that contains all tenant databases 
$tenantServer = $config.TenantServerNameStem + $WtpUser + ".database.windows.net"

# Get 'operations' server that contains catalog database, elastic job database, and other tenant management databases
#$opsServer = <jobAccountServer>

$opsServer = $config.CatalogServerNameStem + $WtpUser + ".database.windows.net"

$jobName = "Extract all tenants ticket purchases to DW"
$jobDescription = "Retrieve ticket sales data from all Wingtip tenants"

$commandText = "
    DECLARE @jobIdentifier uniqueidentifier;
    
    -- Create a target group
    EXEC [jobs].sp_add_target_group @target_group_name = 'TenantGroupDW';

    -- Add all tenant servers to target group
    EXEC [jobs].sp_add_target_group_member
    @target_group_name = 'TenantGroupDW',
    @membership_type = 'Include',
    @target_type = 'SqlServer',
    @refresh_credential_name='$JobExecutionCredentialName',
    @server_name='$tenantServer';

    -- Create elastic job definition
    EXEC jobs.sp_add_job
    @job_name='$jobName',
    @description='$jobDescription',
    @enabled=1,
    @schedule_interval_type='Once',
    @job_id= @jobIdentifier OUTPUT;
    
    -- Add job step to retrieve all tenant ticket purchases
    EXEC jobs.sp_add_jobstep
    @job_name='$jobName',
    @command=N'
    WITH Venues_CTE (VenueId, VenueName, VenueType, VenuePostalCode, VenueCapacity, X)
    AS
    (SELECT TOP 1 Convert(int, HASHBYTES(''md5'',VenueName)) AS VenueId, VenueName, VenueType, PostalCode AS VenuePostalCode,
            (SELECT SUM ([SeatRows]*[SeatsPerRow]) FROM [dbo].[Sections]) AS VenueCapacity,
        1 AS X FROM Venues)
    SELECT v.VenueId, v.VenueName, v.VenueType,v.VenuePostalCode, v.VenueCapacity, tp.TicketPurchaseId, tp.PurchaseDate, tp.PurchaseTotal, c.CustomerId, c.PostalCode as CustomerPostalCode, c.CountryCode, e.EventId, e.EventName, e.Subtitle as EventSubtitle, e.Date as EventDate FROM 
    Venues_CTE as v
    INNER JOIN TicketPurchases AS tp ON v.X = 1
    INNER JOIN Tickets AS t ON t.TicketPurchaseId = tp.TicketPurchaseId
    INNER JOIN Events AS e ON t.EventId = e.EventId
    INNER JOIN Customers AS c ON tp.CustomerId = c.CustomerId',
    @retry_attempts=2,
    @credential_name='$JobExecutionCredentialName',
    @target_group_name='TenantGroupDW',
    @output_type='SqlDatabase',
    @output_credential_name='$JobExecutionCredentialName',
    @output_server_name='$OutputServer',
    @output_database_name='$OutputDataWarehouse',
    @output_table_name='$OutputTableName';
    
    PRINT N'Elastic job submitted';"

    Invoke-Sqlcmd `
    -ServerInstance $opsServer `
    -Username $config.CatalogAdminUserName `
    -Password $config.CatalogAdminPassword `
    -Database $config.JobAccountDatabaseName `
    -Query $commandText `
    -ConnectionTimeout 30 `
    -QueryTimeout 30 `
    -EncryptConnection

Write-output "Copying tenant ticket purchases to '$outputDataWarehouse' ..."

# Check for status of job
$copyComplete = $false 
$completedTenants = @();

while(!$copyComplete)
{
    # Poll for status of copy job
    $jobStatusQuery = "
        SELECT [is_active], [lifecycle] FROM [jobs].[job_executions] 
        WHERE [job_name] = '$jobName' and [step_id] IS NULL"
    
    $jobStatus = Invoke-Sqlcmd `
                    -ServerInstance $opsServer `
                    -Username $config.CatalogAdminUserName `
                    -Password $config.CatalogAdminPassword `
                    -Database $config.JobAccountDatabaseName `
                    -Query $jobStatusQuery `
                    -ConnectionTimeout 30 `
                    -QueryTimeout 30 `
                    -EncryptConnection
    
    if ($jobStatus.lifecycle -eq "Succeeded" -or $jobStatus.lifecycle -eq "Failed")
    {
        $copyComplete = $true
    }

    # Get details on which tenants' purchases have been copied
    $tenantStatusQuery = "
        SELECT [target_database_name], [is_active], [lifecycle], [last_message] FROM [jobs].[job_executions] 
        WHERE [job_name] = '$jobName' and [step_id] IS NOT NULL and [target_database_name] IS NOT NULL"

    $tenantStatus = Invoke-Sqlcmd `
                        -ServerInstance $opsServer `
                        -Username $config.CatalogAdminUserName `
                        -Password $config.CatalogAdminPassword `
                        -Database $config.JobAccountDatabaseName `
                        -Query $tenantStatusQuery `
                        -ConnectionTimeout 30 `
                        -QueryTimeout 30 `
                        -EncryptConnection

    # Print status of tenants' purchases copy job
    foreach($tenant in $tenantStatus)
    {
        if (($tenant.lifecycle -eq "Succeeded") -and ($completedTenants -notcontains $tenant.target_database_name))
        {
            Write-Output "Tenant '$($tenant.target_database_name)' ticket purchases copy complete."
            $completedTenants += $tenant.target_database_name
        }
        elseif ($tenant.lifecycle -eq "Failed")
        {
            Write-Output "Copy ticket purchases job failed for tenant '$($tenant.target_database_name)' with error: $($tenant.last_message) "
        }
    }

    if($copyComplete)
    {
        Write-Output "----Copy tenant ticket purchases job complete ----"
    }
    else
    {
        if ($tenantStatus.Length)
        {
            $inProgressTenants = $tenantStatus.Length - $completedTenants.Length
            Write-Output "----Processing $inProgressTenants tenant(s)----" 
            Start-Sleep -s 5   
        }
    }
    
}

# Cleanup completed job
Write-output "Deleting completed job from job database ..."

$commandText = "
    EXEC [jobs].[sp_delete_job] '$jobName'
    EXEC [jobs].[sp_delete_target_group] 'TenantGroupDW' "
    
    Invoke-Sqlcmd `
        -ServerInstance $opsServer `
        -Username $config.CatalogAdminUserName `
        -Password $config.CatalogAdminPassword `
        -Database $config.JobAccountDatabaseName `
        -Query $commandText `
        -ConnectionTimeout 30 `
        -QueryTimeout 30 `
        -EncryptConnection
