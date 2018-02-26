<#
.Synopsis
  This module implements a PowerShell wrapper around the Azure SQL .NET Fluent APIs.
  It allows PowerShell to issue asynchronous create, update, restore, and failover operations for SQL databases
#>

Import-Module $PSScriptRoot\SubscriptionManagement -Force

# Configure path of libraries
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -parent $MyInvocation.MyCommand.Path
$sqlFluentLib = 'Microsoft.Azure.Management.Sql.Fluent.dll'
$sqlFluentLibPath = "$scriptDir\$sqlFluentLib"
$resourceManagerLib = 'Microsoft.Azure.Management.ResourceManager.Fluent.dll'
$resourceManagerLibPath = "$scriptDir\$resourceManagerLib"

# Download and install libraries from nuget if missing
if (-not $(Test-Path $sqlFluentLibPath))
{
    $message = "'$sqlFluentLib' was not found."
    $question = "Would you like to download it from NuGet?"
    
    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))
    
    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1 <# Default is No #>)
    
    if ($decision -eq 0) # User chose Yes
    {
        $sqlFluentPackage = 'Microsoft.Azure.Management.Sql.Fluent'
        if ($PSVersionTable.PSVersion.Major -ge 5 -and $(Get-PackageProvider -Name nuget -ErrorAction Ignore) -ne $null)
        {
            # Download the package using OneGet
            # For nuget source on package manager, if on api v3, set to api v2: Set-PackageSource -name nuget.org -NewLocation https://www.nuget.org/api/v2
            $package = Find-Package -Name $sqlFluentPackage -ProviderName nuget -Source nuget.org
            $null = $package | Install-Package -Destination $scriptDir
            $null = Copy-Item "$scriptDir\$sqlFluentPackage.$($package.Version)\lib\net452\$sqlFluentLib" $sqlFluentLibPath 
        }
        else
        {
            # Download https://www.nuget.org/nuget.exe and use that to download the package 
            $nugetExePath = "$scriptDir\nuget.exe"
            if (-not $(Test-Path $nugetExePath))
            {
                Invoke-WebRequest 'https://www.nuget.org/nuget.exe' -OutFile $nugetExePath
            }
            $null = &$nugetExePath install $sqlFluentPackage -OutputDirectory $scriptDir -ExcludeVersion
            $null = Copy-Item "$scriptDir\$sqlFluentPackage\lib\net452\$sqlFluentLib" $sqlFluentLibPath
        }
    }    
}
elseif (-not $(Test-Path $resourceManagerLibPath))
{
    $message = "'$resourceManagerLib' was not found."
    $question = "Would you like to download it from NuGet?"
    
    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))
    
    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1 <# Default is No #>)
    
    if ($decision -eq 0) # User chose Yes
    {
        $resManagerPackage = 'Microsoft.Azure.Management.ResourceManager.Fluent'
        if ($PSVersionTable.PSVersion.Major -ge 5 -and $(Get-PackageProvider -Name nuget -ErrorAction Ignore) -ne $null)
        {
            # Download the package using OneGet
            # For nuget source on package manager, if on api v3, set to api v2: Set-PackageSource -name nuget.org -NewLocation https://www.nuget.org/api/v2
            $package = Find-Package -Name $resManagerPackage -ProviderName nuget -Source nuget.org
            $null = $package | Install-Package -Destination $scriptDir
            $null = Copy-Item "$scriptDir\$resManagerPackage.$($package.Version)\lib\net452\$resourceManagerLib" $resourceManagerLibPath 
        }
        else
        {
            # Download https://www.nuget.org/nuget.exe and use that to download the package 
            $nugetExePath = "$scriptDir\nuget.exe"
            if (-not $(Test-Path $nugetExePath))
            {
                Invoke-WebRequest 'https://www.nuget.org/nuget.exe' -OutFile $nugetExePath
            }
            $null = &$nugetExePath install $resManagerPackage -OutputDirectory $scriptDir -ExcludeVersion
            $null = Copy-Item "$scriptDir\$resManagerPackage\lib\net452\$resourceManagerLib" $resourceManagerLibPath
        }
    }
}

# Add assemblies containing Sql Fluent API related types
Add-Type -Path $resourceManagerLibPath
Add-Type -Path $sqlFluentLibPath

## ---------------------------------------Helper Functions----------------------------------------------

<#
.SYNOPSIS
    Gets Azure powershell context and uses this to authenticate to Azure REST API
#>
function Get-RestAPIContext
{
    [OutputType([Microsoft.Azure.Management.Sql.Fluent.SqlManager])]
    param (
        # NoEcho stops the output of the signed in user to prevent double echo  
        [parameter(Mandatory=$false)]
        [switch] $NoEcho
    )

    # Get Azure credentials if not already logged on
    Initialize-Subscription -NoEcho:$NoEcho.IsPresent

    # Get PowerShell credentails object
    $context = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile.DefaultContext
    $credentials = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.GetServiceClientCredentials($context, "ResourceManager")

    # Get REST API client for Azure public global cloud
    $client = [Microsoft.Azure.Management.ResourceManager.Fluent.Core.RestClient]::Configure().WithCredentials($credentials).WithEnvironment([Microsoft.Azure.Management.ResourceManager.Fluent.AzureEnvironment]::AzureGlobalCloud).Build()

    # Authenticate to Fluent API SDK
    $azure = [Microsoft.Azure.Management.Sql.Fluent.SqlManager]::Authenticate($client, $context.Subscription.Id)
 
    return $azure
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
        [object]$AzureContext,

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
    Issues an asynchronous call to geo-restore an Azure SQL database to a different region.
    Returns a .NET Task object that can be used to track the status of the call.
#>
function Invoke-AzureSQLDatabaseGeoRestoreAsync
{
    param(
        [parameter(Mandatory=$true)]
        [object]$AzureContext,

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
        [object]$AzureContext,

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

# # Get db properties if job is complete 
# if ($jobObject.IsCompleted)
# {
#     $dbObject = $jobObject.Result.Body
# }


