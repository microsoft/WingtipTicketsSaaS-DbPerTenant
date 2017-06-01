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

$jobAccountServerName = $config.jobAccountServerNameStem + $WtpUser
$fullyQualifiedjobAccountServerName = $jobAccountServerName + ".database.windows.net"
$databaseName = $config.JobAccountDatabaseName

# Check if the job account already exists and the latest Azure PowerShell SDK has been installed 
try 
{
    $jobaccount = Get-AzureRmSqlJobAccount -ResourceGroupName $WtpResourceGroupName `
        -ServerName $jobAccountServerName `
        -JobAccountName $($config.JobAccount) 
}
catch 
{
    if ($_.Exception.Message -like "*'Get-AzureRmSqlJobAccount' is not recognized*")
    {
        Write-Error "'Get-AzureRmSqlJobAccount' not found. Download and install the Azure PowerShell SDK that includes support for Elastic Jobs: 
        https://github.com/jaredmoo/azure-powershell/releases"
    }
}

# Check if current Azure subscription is signed up for Preview of Elastic jobs 
$registrationStatus = Get-AzureRmProviderFeature -ProviderName Microsoft.Sql -FeatureName sqldb-JobAccounts

if ($registrationStatus.RegistrationState -eq "NotRegistered")
{
    Write-Error "Your current subscription is not white-listed for the preview of Elastic jobs. Please contact Microsoft to white-list your subscription."
    exit
}

# Check the job account database already exists
$database = Get-AzureRmSqlDatabase -ResourceGroupName $WtpResourceGroupName `
    -ServerName $jobAccountServerName `
	-DatabaseName $($config.JobAccountDatabaseName) `
	-ErrorAction SilentlyContinue

# Create the job account database if it doesn't already exist
try
{
	if (!$database)
	{
		Write-output "Deploying job account database: '$($config.JobAccountDatabaseName)' on server '$fullyQualifiedjobAccountServerName'..."
        
        # Create the job account server - continue if it already exists

        New-AzureRmSqlServer `
            -ResourceGroupName $WtpResourceGroupName `
            -Location $config.JobAccountDeploymentLocation `
            -ServerName $jobAccountServerName `
            -SqlAdministratorCredentials $(New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.JobAccountAdminUserName, $(ConvertTo-SecureString -String $config.JobAccountAdminPassword -AsPlainText -Force)) `
            -ErrorAction SilentlyContinue `
            > $null

        # Open firewall for job account server
        New-AzureRmSqlServerFirewallRule `
            -ResourceGroupName $WtpResourceGroupName `
            -ServerName $jobAccountServerName `
            -FirewallRuleName "Open" `
            -StartIpAddress 0.0.0.0 `
            -EndIpAddress 255.255.255.255 `
            -ErrorAction SilentlyContinue `
            > $null
		
		# Create the job account database
		New-AzureRmSqlDatabase `
			-ResourceGroupName $WtpResourceGroupName `
			-ServerName $jobAccountServerName `
			-DatabaseName $($config.JobAccountDatabaseName) `
			-RequestedServiceObjectiveName "S2" `
            > $null	
	}
 }
catch
{
	Write-Error $_.Exception.Message
	Write-Error "An error occured deploying the job account database"
	throw
}

# Create the job account if it doesn't already exist
try
{
	if (!$jobaccount)
	{
		Write-output "Deploying job account: '$($config.JobAccount)'..."
		
		# Create the job account
		New-AzureRmSqlJobAccount `
            -ServerName $jobAccountServerName `
			-JobAccountName $($config.JobAccount) `
			-DatabaseName $($config.JobAccountDatabaseName) `
			-ResourceGroupName $($WtpResourceGroupName) `
            > $null
	}
 }
catch
{
	Write-Error $_.Exception.Message
	Write-Error "An error occured deploying the job account"
	throw
}

$credentialName = $config.JobAccountCredentialName
$commandText = "
    CREATE MASTER KEY;
    GO

    CREATE DATABASE SCOPED CREDENTIAL [$credentialName]
        WITH IDENTITY = N'$($config.JobAccountAdminUserName)', SECRET = N'$($config.JobAccountAdminPassword)';
    GO
    
    CREATE DATABASE SCOPED CREDENTIAL [myrefreshcred]
        WITH IDENTITY = N'$($config.JobAccountAdminUserName)', SECRET = N'$($config.JobAccountAdminPassword)';
    GO
    PRINT N'Database scoped credentials created.';
    "

    Write-output "Initializing database scoped credentials in '$($config.JobAccountDatabaseName)'..."
	
    try
    {    
		Invoke-Sqlcmd `
        -ServerInstance $fullyQualifiedjobAccountServerName `
		-Username $config.JobAccountAdminUserName `
        -Password $config.JobAccountAdminPassword `
		-Database $config.JobAccountDatabaseName `
		-Query $commandText `
		-ConnectionTimeout 30 `
		-QueryTimeout 30 `
		-EncryptConnection
    }
    catch
    {
        #retry once if fails. Query is idempotent.
        Start-Sleep 2
		Invoke-Sqlcmd `
        -ServerInstance $fullyQualifiedjobAccountServerName `
		-Username $config.JobAccountAdminUserName `
        -Password $config.JobAccountAdminPassword `
		-Database $config.JobAccountDatabaseName `
		-Query $commandText `
		-ConnectionTimeout 30 `
		-QueryTimeout 30 `
		-EncryptConnection
    }
	
Write-Output "Deployment of job account database '$($config.JobAccountDatabaseName)' and job account '$($config.JobAccount)' are complete."

