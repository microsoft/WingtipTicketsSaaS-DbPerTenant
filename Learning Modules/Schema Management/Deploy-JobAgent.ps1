[cmdletbinding()]

<#
.SYNOPSIS
  Creates a job agent and associated database   

.DESCRIPTION
  Creates the job agent database and then the job agent. Both are created in the resource group
  created when the Wingtip Tickets application was deployed.

#>
param(
    [Parameter(Mandatory=$true)]
    [string]$WtpResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$WtpUser
)

$ErrorActionPreference = "Stop" 

Import-Module "$PSScriptRoot\..\Common\CatalogAndDatabaseManagement" -Force
Import-Module "$PSScriptRoot\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\WtpConfig" -Force

$config = Get-Configuration

# Get Azure credentials if not already logged on. 
Initialize-Subscription

# Check resource group exists
$resourceGroup = Get-AzureRmResourceGroup -Name $WtpResourceGroupName -ErrorAction SilentlyContinue

if(!$resourceGroup)
{
    throw "Resource group '$WtpResourceGroupName' does not exist.  Exiting..."
}

# Job Agent database is deployed to the catalog server with other singleton management databases in the Wingtip SaaS app 
$catalogServerName = $config.catalogServerNameStem + $WtpUser
$fullyQualifiedCatalogServerName = $catalogServerName + ".database.windows.net"

$jobAgentDatabaseName = $config.JobAgentDatabaseName

# Check if current Azure subscription is signed up for Preview of Elastic jobs 
$registrationStatus = Get-AzureRmProviderFeature -ProviderName Microsoft.Sql -FeatureName sqldb-Jobaccounts

if ($registrationStatus.RegistrationState -ne "Registered")
{
    Write-Error "Your current subscription is not white-listed for the preview of Elastic Jobs. Please contact SaaSFeedback@microsoft.com to white-list your subscription."
    exit
}

# Check if the job agent exists and a version of Azure PowerShell SDK containing the Elastic Jobs cmdlets is installed 
try 
{
    $jobAgent = Get-AzureRmSqlJobAgent `
        -ResourceGroupName $WtpResourceGroupName `
        -ServerName $catalogServerName `
        -JobAgentName $($config.JobAgent) 

    if ($jobAgent)
    {
        Write-output "Job agent already exists"
        exit
    }
}
catch 
{
    if ($_.Exception.Message -like "*'Get-AzureRmSqlJobAgent' is not recognized*")
    {
        Write-Error "'Get-AzureRmSqlJobAgent' not found. Download and install the Azure PowerShell SDK that includes support for Elastic Jobs: https://github.com/jaredmoo/azure-powershell/releases"
        exit
    }
}


# Check if the job agent database exists
$database = Get-AzureRmSqlDatabase `
    -ResourceGroupName $WtpResourceGroupName `
    -ServerName $catalogServerName `
    -DatabaseName $jobAgentDatabaseName `
    -ErrorAction SilentlyContinue

# Create the job agent database if it doesn't exist
try
{
    if (!$database)
    {
        Write-output "Deploying job agent database on server '$catalogServerName'..."
        
        # Create the job agent database
        New-AzureRmSqlDatabase `
            -ResourceGroupName $WtpResourceGroupName `
            -ServerName $catalogServerName `
            -DatabaseName $jobAgentDatabaseName `
            -RequestedServiceObjectiveName $($config.JobAgentDatabaseServiceObjective) `
            > $null 
    }

    # Initialize the job Agent database credentials if they don't exist
    $commandText = "SELECT name, credential_id from sys.database_credentials"
    $availableCredentials = Invoke-SqlcmdWithRetry `
                                -ServerInstance $fullyQualifiedCatalogServerName `
                                -Username $config.CatalogAdminUserName `
                                -Password $config.CatalogAdminPassword `
                                -Database $jobAgentDatabaseName `
                                -Query $commandText `
                                -ConnectionTimeout 30 `
                                -QueryTimeout 30

    if (!$availableCredentials)
    {
        $credentialName = $config.JobAgentCredentialName
        $commandText = "
            CREATE MASTER KEY;
            GO

            CREATE DATABASE SCOPED CREDENTIAL [$credentialName]
                WITH IDENTITY = N'$($config.CatalogAdminUserName)', SECRET = N'$($config.CatalogAdminPassword)';
            GO
    
            CREATE DATABASE SCOPED CREDENTIAL [myrefreshcred]
                WITH IDENTITY = N'$($config.CatalogAdminUserName)', SECRET = N'$($config.CatalogAdminPassword)';
            GO
            PRINT N'Database scoped credentials created.';
            "

        Write-output "Initializing database scoped credentials in database '$jobAgentDatabaseName' ..."

        Invoke-SqlcmdWithRetry `
            -ServerInstance $fullyQualifiedCatalogServerName `
            -Username $config.CatalogAdminUserName `
            -Password $config.CatalogAdminPassword `
            -Database $jobAgentDatabaseName `
            -Query $commandText `
            -ConnectionTimeout 30 `
            -QueryTimeout 30 `
            > $null
    }
}
catch
{
    Write-Error $_.Exception.Message
    Write-Error "An error occured deploying the job agent database"
    throw
}

# Create the job agent
try
{
    Write-output "Deploying job agent ..."
        
    # Create the job agent
    New-AzureRmSqlJobAgent `
        -ServerName $catalogServerName `
        -JobAgentName $($config.JobAgent) `
        -DatabaseName $jobAgentDatabaseName `
        -ResourceGroupName $WtpResourceGroupName `
        > $null 
 }
catch
{
    Write-Error $_.Exception.Message
    Write-Error "An error occured deploying the job agent"
    throw
}
    
Write-Output "Deployment of job agent database and job agent is complete."
