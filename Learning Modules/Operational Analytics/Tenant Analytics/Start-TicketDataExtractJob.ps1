<#
.SYNOPSIS
  Extracts ticket sales data from a tenant database to an analysis database or data warehouse

.DESCRIPTION
  Creates an Elastic Job that extracts ticket sales data from a tenant database and 
  outputs it to an analysis database or data warehouse #>
param(
    [Parameter(Mandatory=$true)]
    [string]$WtpResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$WtpUser,

    [Parameter(Mandatory=$true)]
    [string]$JobExecutionCredentialName,

    [Parameter(Mandatory=$true)]
    [string]$TargetGroupName,

    [Parameter(Mandatory=$true)]
    [string]$OutputServer,

    [Parameter(Mandatory=$true)]
    [string]$OutputDatabase,

    [Parameter(Mandatory=$true)]
    [string]$OutputServerCredentialName,

    [Parameter(Mandatory=$false)]
    [string]$OutputTableName = "AllTicketsPurchasesFromAllTenants",

    [Parameter(Mandatory=$false)]
    [string]$JobName = "Extract all tenants ticket purchases"
)

Import-Module $PSScriptRoot\..\..\Common\CatalogAndDatabaseManagement -Force
Import-Module $PSScriptRoot\..\..\Common\SubscriptionManagement -Force


# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription

Import-Module $PSScriptRoot\..\..\WtpConfig -Force

$config = Get-Configuration

# Get server that contains all tenant databases 
$tenantServer = $config.TenantServerNameStem + $WtpUser + ".database.windows.net"

# Get server that contains job account database
$jobAccountServer = $config.JobAccountServerNameStem + $WtpUser + ".database.windows.net"

$jobName = $JobName
$jobDescription = "Retrieve ticket sales data from all Wingtip tenants"

$commandText = "
        
    -- Create a target group
    EXEC [jobs].sp_add_target_group @target_group_name = '$TargetGroupName';

    -- Add all tenant servers to target group
    EXEC [jobs].sp_add_target_group_member
    @target_group_name = '$TargetGroupName',
    @membership_type = 'Include',
    @target_type = 'SqlServer',
    @refresh_credential_name='$JobExecutionCredentialName',
    @server_name='$tenantServer';

    -- Create elastic job definition
    EXEC jobs.sp_add_job
    @job_name='$jobName',
    @description='$jobDescription',
    @enabled=1,
    @schedule_interval_type='Once';
        
    -- Add job step to retrieve all tenant ticket purchases
    EXEC jobs.sp_add_jobstep
    @job_name='$jobName',
    @command=N'
    SELECT VenueId, VenueName, VenueType, VenuePostalCode, VenueCapacity, TicketPurchaseId, PurchaseDate, PurchaseTotal, RowNumber, SeatNumber, CustomerId, CustomerPostalCode, CountryCode, EventId, EventName, EventSubtitle, EventDate, `$(job_execution_id) as job_execution_id  
    FROM TicketFacts',
    @retry_attempts=2,
    @credential_name='$JobExecutionCredentialName',
    @target_group_name='$TargetGroupName',
    @output_type='SqlDatabase',
    @output_credential_name='$JobExecutionCredentialName',
    @output_server_name='$OutputServer',
    @output_database_name='$OutputDatabase',
    @output_table_name='$OutputTableName';
    
    PRINT N'Elastic job submitted';"

    Invoke-SqlAzureWithRetry `
    -ServerInstance $jobAccountServer `
    -Username $config.JobAccountAdminUserName `
    -Password $config.JobAccountAdminPassword `
    -Database $config.JobAccountDatabaseName `
    -Query $commandText `
    -ConnectionTimeout 30 `
    -QueryTimeout 30 `
    -ErrorAction Stop

Write-output "Copying tenant ticket purchases to '$OutputDatabase' ..."

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
                    -ServerInstance $jobAccountServer `
                    -Username $config.JobAccountAdminUserName `
                    -Password $config.JobAccountAdminPassword `
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
                        -ServerInstance $jobAccountServer `
                        -Username $config.JobAccountAdminUserName `
                        -Password $config.JobAccountAdminPassword `
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
            Write-Output "----Job Executions running in $inProgressTenants tenant(s)----" 
            Start-Sleep -s 5   
        }
    }
    
}

# Cleanup completed job
Write-output "Deleting completed job from job database ..."

$commandText = "
    EXEC [jobs].[sp_delete_job] '$jobName'
    EXEC [jobs].[sp_delete_target_group] '$TargetGroupName' "
    
    Invoke-Sqlcmd `
        -ServerInstance $jobAccountServer `
        -Username $config.JobAccountAdminUserName `
        -Password $config.JobAccountAdminPassword `
        -Database $config.JobAccountDatabaseName `
        -Query $commandText `
        -ConnectionTimeout 30 `
        -QueryTimeout 30 `
        -EncryptConnection
