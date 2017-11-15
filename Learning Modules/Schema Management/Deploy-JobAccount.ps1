[cmdletbinding()]

<#
.SYNOPSIS
  Creates an elastic job account and associated database   

.DESCRIPTION
  Creates the Job account database and then the job account. Both are created in the resource group
  created when the WTP application was deployed.

#>
param(
    [Parameter(Mandatory=$true)]
    [string]$WtpResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$WtpUser
)

$ErrorActionPreference = "Stop" 

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

# Job account database is deployed to the catalog server with other singleton management databases in the Wingtip SaaS app 
$catalogServerName = $config.catalogServerNameStem + $WtpUser
$fullyQualifiedCatalogServerName = $catalogServerName + ".database.windows.net"

$jobAccountDatabaseName = $config.JobAccountDatabaseName

# Check if current Azure subscription is signed up for Preview of Elastic jobs 
$registrationStatus = Get-AzureRmProviderFeature -ProviderName Microsoft.Sql -FeatureName sqldb-JobAccounts

if ($registrationStatus.RegistrationState -ne "Registered")
{
    Write-Error "Your current subscription is not white-listed for the preview of Elastic jobs. Please contact Microsoft to white-list your subscription."
    exit
}

# Check if the job account exists and a version of Azure PowerShell SDK containing the Elastic Jobs cmdlets is installed 
try 
{
    $jobaccount = Get-AzureRmSqlJobAccount `
        -ResourceGroupName $WtpResourceGroupName `
        -ServerName $catalogServerName `
        -JobAccountName $($config.JobAccount) 

    if ($jobAccount)
    {
        Write-output "Job account already exists"
        exit
    }
}
catch 
{
    if ($_.Exception.Message -like "*'Get-AzureRmSqlJobAccount' is not recognized*")
    {
        Write-Error "'Get-AzureRmSqlJobAccount' not found. Download and install the Azure PowerShell SDK that includes support for Elastic Jobs: https://github.com/jaredmoo/azure-powershell/releases"
        exit
    }
}


# Check if the job account database exists
$database = Get-AzureRmSqlDatabase `
    -ResourceGroupName $WtpResourceGroupName `
    -ServerName $catalogServerName `
	-DatabaseName $jobAccountDatabaseName `
	-ErrorAction SilentlyContinue

# Create the job account database if it doesn't exist
try
{
	if (!$database)
	{
		Write-output "Deploying job account database on server '$catalogServerName'..."
        
		# Create the job account database
		New-AzureRmSqlDatabase `
			-ResourceGroupName $WtpResourceGroupName `
			-ServerName $catalogServerName `
			-DatabaseName $jobAccountDatabaseName `
			-RequestedServiceObjectiveName $($config.JobAccountDatabaseServiceObjective) `
            > $null	

        # initialize the job account database credentials
        $credentialName = $config.JobAccountCredentialName
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

        Write-output "Initializing database scoped credentials in database '$jobAccountDatabaseName' ..."
	  
	    Invoke-SqlcmdWithRetry `
        -ServerInstance $fullyQualifiedCatalogServerName `
	    -Username $config.CatalogAdminUserName `
        -Password $config.CatalogAdminPassword `
	    -Database $jobAccountDatabaseName `
	    -Query $commandText `
	    -ConnectionTimeout 30 `
	    -QueryTimeout 30 `
        > $null  

	}
 }
catch
{
	Write-Error $_.Exception.Message
	Write-Error "An error occured deploying the job account database"
	throw
}

# Create the job account
try
{
	Write-output "Deploying job account ..."
		
	# Create the job account
	New-AzureRmSqlJobAccount `
        -ServerName $catalogServerName `
		-JobAccountName $($config.JobAccount) `
		-DatabaseName $jobAccountDatabaseName `
		-ResourceGroupName $WtpResourceGroupName `
        > $null	
 }
catch
{
	Write-Error $_.Exception.Message
	Write-Error "An error occured deploying the job account"
	throw
}
	
Write-Output "Deployment of job account database and job account is complete."