<#
.Synopsis
  This module implements a PowerShell wrapper around the Azure SQL .NET Fluent APIs.
  It allows PowerShell to issue asynchronous create, update, restore, and failover operations for SQL databases
#>

Import-Module $PSScriptRoot\SubscriptionManagement -Force

# Get Sql Fluent library if it exists
$ErrorActionPreference = "Stop"
$libPath = "$(Split-Path -parent $MyInvocation.MyCommand.Path)\Lib"
$sqlFluentLib = 'Microsoft.Azure.Management.Sql.Fluent.dll'
$sqlFluentPath = "$libPath\$sqlFluentLib"

# Install Sql Fluent API nuget package if it is not present.
# The code below assumes that all dependencies are installed if Sql Fluent library is present. Install other required dependencies if this is not the case
if (!$(Test-Path $sqlFluentPath))
{
    # Download and install libraries from nuget if missing
    $message = "'$sqlFluentLib' was not found in libary folder."
    $question = "Would you like to download it from NuGet?"
    
    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))
    
    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1 <# Default is No #>)
    
    if ($decision -eq 0) # User chose Yes
    {
        $nugetPackageLocation = "$Env:UserProfile\.nuget\packages"
        $sqlFluentPackageName = 'Microsoft.Azure.Management.Sql.Fluent'

        if ($PSVersionTable.PSVersion.Major -ge 5 -and $(Get-PackageProvider -Name nuget -ErrorAction Ignore) -ne $null)
        {
            # Download the package using OneGet
            # For nuget source on package manager, if on api v3, set to api v2: Set-PackageSource -name nuget.org -NewLocation https://www.nuget.org/api/v2
            $package = Find-Package -Name $sqlFluentPackageName -ProviderName nuget -Source nuget.org
            $null = $package | Install-Package -Destination $nugetPackageLocation           
        }
        else
        {
            # Download https://www.nuget.org/nuget.exe and use that to download the package 
            $nugetExePath = "$scriptDir\nuget.exe"
            if (-not $(Test-Path $nugetExePath))
            {
                Invoke-WebRequest 'https://www.nuget.org/nuget.exe' -OutFile $nugetExePath
            }
            $null = &$nugetExePath install $sqlFluentPackageName -OutputDirectory $nugetPackageLocation -ExcludeVersion
        } 

        $jsonPackageName = 'NewtonSoft.Json'
        $restClientRuntimePackageName = 'Microsoft.Rest.ClientRuntime'
        $sqlFluentPackageName = 'Microsoft.Azure.Management.Sql.Fluent'
        $azureRestClientRuntimePackageName = 'Microsoft.Rest.ClientRuntime.Azure'
        $resManagerFluentPackageName = 'Microsoft.Azure.Management.ResourceManager.Fluent'
        $activeDirectoryModelPackageName = 'Microsoft.IdentityModel.Clients.ActiveDirectory'
        $azureRestClientAuthenticationPackageName = 'Microsoft.Rest.ClientRuntime.Azure.Authentication'

        # Get package install locations
        $jsonPackageLocation = Split-Path "$((Get-Package -Name $jsonPackageName -MinimumVersion 6.0.8).Source)" -Parent
        $restClientRuntimePackageLocation = Split-Path "$((Get-Package -Name $restClientRuntimePackageName -MinimumVersion 2.3.9 -MaximumVersion 3.0.0).Source)" -Parent
        $sqlFluentPackageLocation = Split-Path "$((Get-Package -Name $sqlFluentPackageName -MinimumVersion 1.6.0).Source)" -Parent
        $azureRestClientRuntimePackageLocation = Split-Path "$((Get-Package -Name $azureRestClientRuntimePackageName -MinimumVersion 3.3.10).Source)" -Parent
        $resManagerPackageLocation = Split-Path "$((Get-Package -Name $resManagerFluentPackageName -MinimumVersion 1.6.0).Source)" -Parent
        $activeDirectoryModelPackageLocation = Split-Path "$((Get-Package -Name $activeDirectoryModelPackageName -MinimumVersion 2.28.3 -MaximumVersion 4.0.0).Source)" -Parent
        $azureRestClientAuthenticationPackageLocation = Split-Path "$((Get-Package -Name $azureRestClientAuthenticationPackageName -MinimumVersion 2.3.2).Source)" -Parent

        # Add required DLLs to library folder
        # Note: The locations below are for the .NET framework and not .NET standard
        $null = Copy-Item "$jsonPackageLocation\lib\net45\$jsonPackageName.dll" -Destination $libPath
        $null = Copy-Item "$restClientRuntimePackageLocation\lib\net452\$restClientRuntimePackageName.dll" -Destination $libPath
        $null = Copy-Item "$sqlFluentPackageLocation\lib\net452\$sqlFluentPackageName.dll" -Destination $libPath
        $null = Copy-Item "$azureRestClientRuntimePackageLocation\lib\net452\$azureRestClientRuntimePackageName.dll" -Destination $libPath
        $null = Copy-Item "$resManagerPackageLocation\lib\net452\$resManagerFluentPackageName.dll" -Destination $libPath
        $null = Copy-Item "$activeDirectoryModelPackageLocation\lib\net45\$activeDirectoryModelPackageName.dll" -Destination $libPath
        $null = Copy-Item "$azureRestClientAuthenticationPackageLocation\lib\net452\$azureRestClientAuthenticationPackageName.dll" -Destination $libPath
    }    
}

# Add assemblies containing Sql Fluent API related types
try 
{
    Add-Type -Path $sqlFluentPath
}
catch [System.Reflection.ReflectionTypeLoadException]
{
    Write-Host "Error Message: $($_.Exception.Message)"
    Write-Error "LoaderExceptions: $($_.Exception.LoaderExceptions[0])"
}

## ---------------------------------------Helper Functions----------------------------------------------

<#
.SYNOPSIS
    Gets Azure powershell context and uses this to authenticate to Azure REST API
#>
function Get-RestAPIContext
{
    # Get Azure credentials if not already logged on
    Initialize-Subscription -NoEcho >$null

    # Get PowerShell credentails object
    $context = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile.DefaultContext
    $credentials = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.GetServiceClientCredentials($context, "ResourceManager")

    # Get REST API client for Azure public global cloud
    $client = [Microsoft.Azure.Management.ResourceManager.Fluent.Core.RestClient]::Configure().WithCredentials($credentials).WithEnvironment([Microsoft.Azure.Management.ResourceManager.Fluent.AzureEnvironment]::AzureGlobalCloud).Build()

    # Authenticate to Fluent API SDK
    return [Microsoft.Azure.Management.Sql.Fluent.SqlManager]::Authenticate($client, $context.Subscription.Id) 
}

<#
.SYNOPSIS
    Issues an asynchronous call to create a new Azure SQL database. This function can also update an existing Azure SQL database. 
    Returns a .NET Task object that can be used to track the status of the call.
#>
function New-AzureSQLDatabaseAsync
{
    param(
        [parameter(Mandatory=$true)]
        [Microsoft.Azure.Management.Sql.Fluent.SqlManager]$AzureContext,

        [parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [parameter(Mandatory=$true)]
        [string]$Location,

        [parameter(Mandatory=$true)]
        [string]$ServerName,

        [parameter(Mandatory=$true)]
        [string]$DatabaseName,

        [parameter(Mandatory=$false)]
        [string]$RequestedServiceObjectiveName,

        [parameter(Mandatory=$false)]
        [string]$ElasticPoolName
    )

    $dbProperties = New-Object Microsoft.Azure.Management.Sql.Fluent.Models.DatabaseInner 
    $dbProperties.Location = $Location

    if ($RequestedServiceObjectiveName)
    {
        $dbProperties.RequestedServiceObjectiveName = $RequestedServiceObjectiveName
    }
    elseif ($ElasticPoolName)
    {
        $dbProperties.ElasticPoolName = $ElasticPoolName
    }

    # Start asynchronous call to create database
    $jobObject = $AzureContext.Inner.Databases.CreateOrUpdateWithHttpMessagesAsync($ResourceGroupName, $ServerName, $DatabaseName, $dbProperties)
    return $jobObject
}

<#
.SYNOPSIS
    Issues an asynchronous call to create a readable replica for an Azure SQL database.
    Returns a .NET Task object that can be used to track the status of the call.
#>
function New-AzureSQLDatabaseReplicaAsync
{
    param(
        [parameter(Mandatory=$true)]
        [Microsoft.Azure.Management.Sql.Fluent.SqlManager]$AzureContext,

        [parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [parameter(Mandatory=$true)]
        [string]$Location,

        [parameter(Mandatory=$true)]
        [string]$ServerName,

        [parameter(Mandatory=$true)]
        [string]$DatabaseName,

        [parameter(Mandatory=$true)]
        [string]$SourceDatabaseId,

        [parameter(Mandatory=$false)]
        [string]$RequestedServiceObjectiveName,

        [parameter(Mandatory=$false)]
        [string]$ElasticPoolName
    )

    $dbProperties = New-Object Microsoft.Azure.Management.Sql.Fluent.Models.DatabaseInner 
    $dbProperties.CreateMode = 'OnlineSecondary'
    $dbProperties.Location = $Location
    $dbProperties.SourceDatabaseId = $SourceDatabaseId

    if ($RequestedServiceObjectiveName)
    {
        $dbProperties.RequestedServiceObjectiveName = $RequestedServiceObjectiveName
    }
    elseif ($ElasticPoolName)
    {
        $dbProperties.ElasticPoolName = $ElasticPoolName
    }

    # Start asynchronous call to create replica
    $jobObject = $AzureContext.Inner.Databases.CreateOrUpdateWithHttpMessagesAsync($ResourceGroupName, $ServerName, $DatabaseName, $dbProperties)
    return $jobObject
}

<#
.SYNOPSIS
    Issues an asynchronous call to geo-restore an Azure SQL database to a different region.
    Returns a .NET Task object that can be used to track the status of the call.
#>
function Invoke-AzureSQLDatabaseGeoRestoreAsync
{
    param(
        [parameter(Mandatory=$true)]
        [Microsoft.Azure.Management.Sql.Fluent.SqlManager]$AzureContext,

        [parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [parameter(Mandatory=$true)]
        [string]$Location,

        [parameter(Mandatory=$true)]
        [string]$ServerName,

        [parameter(Mandatory=$true)]
        [string]$DatabaseName,

        [parameter(Mandatory=$true)]
        [string]$SourceDatabaseId,

        [parameter(Mandatory=$false)]
        [string]$RequestedServiceObjectiveName,

        [parameter(Mandatory=$false)]
        [string]$ElasticPoolName
    )

    $dbProperties = New-Object Microsoft.Azure.Management.Sql.Fluent.Models.DatabaseInner 
    $dbProperties.CreateMode = 'Recovery'
    $dbProperties.Location = $Location
    $dbProperties.SourceDatabaseId = $SourceDatabaseId

    if ($RequestedServiceObjectiveName)
    {
        $dbProperties.RequestedServiceObjectiveName = $RequestedServiceObjectiveName
    }
    elseif ($ElasticPoolName)
    {
        $dbProperties.ElasticPoolName = $ElasticPoolName
    }

    # Start asynchronous call to create database
    $jobObject = $AzureContext.Inner.Databases.CreateOrUpdateWithHttpMessagesAsync($ResourceGroupName, $ServerName, $DatabaseName, $dbProperties)
    return $jobObject
}

<#
.SYNOPSIS
    Issues an asynchronous call to failover an Azure SQL database to a secondary server.
    Returns a .NET Task object that can be used to track the status of the call.
#>
function Invoke-AzureSQLDatabaseFailoverAsync
{
    param(
        [parameter(Mandatory=$true)]
        [Microsoft.Azure.Management.Sql.Fluent.SqlManager]$AzureContext,

        [parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [parameter(Mandatory=$true)]
        [string]$ServerName,

        [parameter(Mandatory=$true)]
        [string]$DatabaseName,

        [parameter(Mandatory=$true)]
        [string]$ReplicationLinkId,

        [parameter(Mandatory=$false)]
        [switch]$AllowDataLoss     
    )

    if (!$AllowDataLoss)
    {
        # Start asynchronous call to failover database for a DR drill
        $jobObject = $AzureContext.Inner.Databases.FailoverReplicationLinkWithHttpMessagesAsync($ResourceGroupName, $ServerName, $DatabaseName, $ReplicationLinkId)
    }
    else
    {
        # Start asynchronous call to failover database with the possibility of data loss
        $jobObject = $AzureContext.Inner.Databases.FailoverReplicationLinkAllowDataLossWithHttpMessagesAsync($ResourceGroupName, $ServerName, $DatabaseName, $ReplicationLinkId)
    }
    return $jobObject
}

<#
.SYNOPSIS
    Issues an asynchronous call to cancel an ongoing Azure SQL database operation.
    Returns a .NET Task object that can be used to track the response of the call.
#>
function Invoke-CancelAzureSqlDatabaseOperation
{
    param(
        [parameter(Mandatory=$true)]
        [Microsoft.Azure.Management.Sql.Fluent.SqlManager]$AzureContext,

        [parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [parameter(Mandatory=$true)]
        [string]$ServerName,

        [parameter(Mandatory=$true)]
        [string]$DatabaseName,

        [parameter(Mandatory=$true)]
        [Guid]$OperationId      
    )

    # Cancel database operation
    $jobObject = $AzureContext.Inner.Databases.CancelWithHttpMessagesAsync($ResourceGroupName, $ServerName, $DatabaseName, $OperationId)
    return $jobObject
}
