<#
/********************************************************
*                                                        *
*   © Microsoft. All rights reserved.                    *
*                                                        *
*********************************************************/

.SYNOPSIS
    Provides a set of methods to interact with
    Elastic Scale Shard Management functionality

.NOTES
    Author: Microsoft Azure SQL DB Elastic Scale team
    Last Updated: 9/16/2014
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Determine where the Elastic DB Client Library should be
$ScriptDir = Split-Path -parent $MyInvocation.MyCommand.Path
$edclFile = 'Microsoft.Azure.SqlDatabase.ElasticScale.Client.dll'
$edclPath = "$ScriptDir\$edclFile"

if (-not $(Test-Path $edclPath))
{
    # EDCL is missing
    $message = "$edclPath was not found."
    $question = "Would you like to download it from NuGet?"
    
    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))
    
    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1 <# Default is No #>)
    
    if ($decision -eq 0) # User chose Yes
    {
        $edclPackage = 'Microsoft.Azure.SqlDatabase.ElasticScale.Client'
        if ($PSVersionTable.PSVersion.Major -ge 5 `
            -and $(Get-PackageProvider -Name nuget -ErrorAction Ignore) -ne $null)
        {
            # Download the package using OneGet
            $package = Find-Package -Name $edclPackage -ProviderName nuget -Source nuget.org
            $null = $package | Install-Package -Destination $ScriptDir
            $null = copy "$ScriptDir\$edclPackage.$($package.Version)\lib\net45\$edclFile" $edclPath 
        }
        else
        {
            # Download https://www.nuget.org/nuget.exe and use that to download the package 
            $nugetExePath = "$ScriptDir\nuget.exe"
            if (-not $(Test-Path $nugetExePath))
            {
                Invoke-WebRequest 'https://www.nuget.org/nuget.exe' -OutFile $nugetExePath
            }
            $null = &$nugetExePath install $edclPackage -OutputDirectory $ScriptDir -ExcludeVersion
            $null = copy "$ScriptDir\$edclPackage\lib\net45\$edclFile" $edclPath
        }
    }
    
    # If user chose No or if the download failed for some reason, then Add-Type below will fail
    # and that will give an error message saying that the file does not exist. 
}

# Add assemblies containing Shard Management related types
Add-Type -Path $edclPath

<#
.SYNOPSIS
    Shard map manager enables one to add, modify, delete shard entries and ranges
#>
function New-ShardMapManager
{
    # Return either a Shard Map Manager object or null reference
    [OutputType([Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManager])]
    param (
        # User name for the shard map manager DB      
        [parameter(Mandatory=$true)]
        [String]$UserName,

        #Password for the shard map manager DB
        [parameter(Mandatory=$true)]
        [String]$Password,

        # Server name for the shard map manager DB
        [parameter(Mandatory=$true)]
        [String]$SqlServerName,

        # DB name for the shard map manager
        [parameter(Mandatory=$true)]
        [String]$SqlDatabaseName,

        # Application name             
        [parameter(Mandatory=$false)]
        [String]$AppName = "ESC_SEv1.0",
        
        [parameter()]
        [bool]$ReplaceExisting = $false
    )

    Write-Verbose "Creating Shard Map Manager in $SqlServerName.$SqlDatabaseName"

    # Reference assemblies containing Shard Management related types
    [Type]$ShardMapManagementFactoryType = [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManagerFactory]

    # Build credentials for Shard Map Manager DB and Shard DBs
    $SmmConnectionString = "Server=$SqlServerName; Initial Catalog=$SqlDatabaseName; User ID=$UserName; Password=$Password; Application Name = $AppName;"

    # Create the Shard Map Manager
    if ($ReplaceExisting)
    {
        $CreateMode = [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManagerCreateMode]::ReplaceExisting
    }
    else
    {
        $CreateMode = [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManagerCreateMode]::KeepExisting
    }
 
    return $ShardMapManagementFactoryType::CreateSqlShardMapManager($SmmConnectionString, $CreateMode)
}

<#
.SYNOPSIS
    Shard map manager enables one to add, modify, delete shard entries and ranges
#>
function Get-ShardMapManager
{
    # Return either a Shard Map Manager object or null reference
    [OutputType([Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManager])]
    param (
        # User name for the shard map manager DB      
        [parameter(Mandatory=$true)]
        [String]$UserName,

        #Password for the shard map manager DB
        [parameter(Mandatory=$true)]
        [String]$Password,

        # Server name for the shard map manager DB
        [parameter(Mandatory=$true)]
        [String]$SqlServerName,

        # DB name for the shard map manager
        [parameter(Mandatory=$true)]
        [String]$SqlDatabaseName,

        # Application name             
        [parameter(Mandatory=$false)]
        [String]$AppName = "ESC_SEv1.0"
    )

    Write-Verbose "Getting Shard Map Manager in $SqlServerName.$SqlDatabaseName"

    
    # Reference assemblies containing Shard Management related types
    [Type]$ShardMapManagementFactoryType = [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManagerFactory]

    # Build credentials for Shard Map Manager DB and Shard DBs
    $SmmConnectionString = "Server=$SqlServerName; Initial Catalog=$SqlDatabaseName; User ID=$UserName; Password=$Password; Application Name = $AppName;"

    # Check if a shard map manager exists on $SqlDatabaseName
    $LoadPolicy = [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManagerLoadPolicy]::Lazy
    [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManager]$ShardMapManager = $null
    $Exists = $ShardMapManagementFactoryType::TryGetSqlShardMapManager($SmmConnectionString, $LoadPolicy, [ref]$ShardMapManager)
    
    return $ShardMapManager
   
}

<#
.SYNOPSIS
    Creates a new RangeShardMap<$KeyType>
#>
function New-RangeShardMap
{
    # Return a range shard map or null reference if the range shard map does not exist
    param 
    (
         # Type of range shard map
        [parameter(Mandatory=$true)]
        [Type]$KeyType,

        # Shard map manager object      
        [parameter(Mandatory=$true)]
        [System.Object]$ShardMapManager,

        # Name of the range 
        [parameter(Mandatory=$true)]
        [String]$RangeShardMapName
    )

    Write-Verbose "Creating Range Shard Map"
    
    # Get and cast necessary shard map management methods for a range shard map
    [Type]$ShardMapManagerType = [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManager]
    $CreateRangeShardMapMethodGeneric = $ShardMapManagerType.GetMethod("CreateRangeShardMap")
    $CreateRangeShardMapMethodTyped = $CreateRangeShardMapMethodGeneric.MakeGenericMethod($KeyType)

    # Create the shard map
    $params = @($RangeShardMapName)
    return $CreateRangeShardMapMethodTyped.Invoke($ShardMapManager, $params)
}

<#
.SYNOPSIS
    Gets a RangeShardMap<$KeyType>
#>
function Get-RangeShardMap
{
    param 
    (
        # Type of range shard map
        [parameter(Mandatory=$true)]
        [Type]$KeyType,

        # Shard map manager object      
        [parameter(Mandatory=$true)]
        [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManager]$ShardMapManager,

        # Name of the range 
        [parameter(Mandatory=$true)]
        [String]$RangeShardMapName
    )
    
    # Get and cast necessary shard map management methods for a range shard map
    [Type]$ShardMapManagerType = [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManager]
    $GetRangeShardMapMethodGeneric = $ShardMapManagerType.GetMethod("GetRangeShardMap")
    $GetRangeShardMapMethodTyped = $GetRangeShardMapMethodGeneric.MakeGenericMethod($KeyType)

    # Get range shard map
    $GetRangeShardMapMethodTyped.Invoke($ShardMapManager, $RangeShardMapName)
}

<#
.SYNOPSIS
    Registers a particular database as a shard within a particular range shard map
#>
function Add-Shard
{
    param 
    (
        # Target shard map     
        [parameter(Mandatory=$true)]
        [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMap]$ShardMap,

        # SQL Server name for which the database is attributed to
        [parameter(Mandatory=$true)]
        [String]$SqlServerName,

        # Database to be added to the shard map
        [parameter(Mandatory=$true)]
        [String]$SqlDatabaseName
    )
    
    # Add new shard location to shard map
    $ShardLocation = New-Object Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardLocation($SqlServerName, $SqlDatabaseName)

    # Initialize reference for shard new shard
    [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.Shard]$ShardReference = $null

    Write-Verbose "`tChecking if shard $ShardLocation is registered with the shard map manager..."

    # Check to see if shard already exists 
    if ($ShardMap.TryGetShard($ShardLocation, [ref]$ShardReference))
    {
        Write-Verbose "`tShard $SqlDatabaseName already registered with the shard map manager"
        $InputShard = $ShardReference
    }
    else
    {
        Write-Verbose "`tShard $ShardLocation does not exist in the shard map manager, adding..."
        
        # Add $ShardName as a shard in the shard map manager
        $ShardMapReturn = $ShardMap.CreateShard($ShardLocation)

        Write-Verbose "`tShard $ShardLocation added to the shard map manager"
    }
}

<#
.SYNOPSIS
    Adds a low and high value for a particular shard to a range shard map
#>
function Add-RangeMapping
{
    param 
    (
         # Type of range shard map
        [parameter(Mandatory=$true)]
        [Type]$KeyType,

        [parameter(Mandatory=$true)]
        [System.Object]$RangeShardMap,

        [parameter(Mandatory=$true)]
        [object]$RangeLow,

        [parameter(Mandatory=$true)]
        [object]$RangeHigh,

        [parameter(Mandatory=$true)]
        [String]$SqlServerName,

        [parameter(Mandatory=$true)]
        [String]$SqlDatabaseName
    )
      
    # Add new shard location to range shard map
    $ShardLocation = New-Object Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardLocation($SqlServerName, $SqlDatabaseName)

    # Check if the range mapping already exists in the shard map manager    
    $InputShard = $rangeShardMap.GetShard($ShardLocation)
    $InputRange = New-Object Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.Range[$KeyType]($RangeLow, $RangeHigh)
    
    Write-Verbose "`tChecking if range [$RangeLow, $RangeHigh) exists for $SqlDatabaseName..."

    $Mappings = $RangeShardMap.GetMappings($InputRange)

    if($Mappings.count -gt 0 -and $Mappings[0].Value -eq $InputRange)
    {
        Write-Verbose "`tRange [$RangeLow, $RangeHigh) already exists for $SqlDatabaseName"
    }
    else
    {
        Write-Verbose "`tRange [$RangeLow, $RangeHigh) for $SqlDatabaseName does not exist, adding..."
        $ShardReference = $rangeShardMap.CreateRangeMapping($InputRange, $InputShard)
        Write-Verbose "`tNew range [$RangeLow, $RangeHigh) for $SqlDatabaseName added to range shard map"
    }
}

<#
.SYNOPSIS
    Updates the shard for an existing mapping in a range shard map
#>
function Set-RangeMapping
{
    param
    (
         # Type of range shard map
        [parameter(Mandatory=$true)]
        [Type]$KeyType,

        [parameter(Mandatory=$true)]
        [System.Object]$RangeShardMap,

        [parameter(Mandatory=$true)]
        [object]$RangeLow,

        [parameter(Mandatory=$true)]
        [object]$RangeHigh,

        [parameter(Mandatory=$true)]
        [String]$SqlServerName,

        [parameter(Mandatory=$true)]
        [String]$SqlDatabaseName
    )

    # Get the Shard from the shard map
    $ShardLocation = New-Object Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardLocation($SqlServerName, $SqlDatabaseName)
    $InputShard = $rangeShardMap.GetShard($ShardLocation)

    # Get the RangeMapping from the shard map
    $InputRange = New-Object Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.Range[$KeyType]($RangeLow, $RangeHigh)
    Write-Verbose "`tChecking if range [$RangeLow, $RangeHigh) exists for $SqlDatabaseName..."
    $Mappings = $RangeShardMap.GetMappings($InputRange)

    Write-Verbose "Mappings found: $($Mappings | Out-Mapping | Format-Table | Out-String)"

    if ($Mappings.count -eq 1 -and $Mappings[0].Value -eq $InputRange)
    {
        $Mapping = $Mappings[0]

        Write-Verbose "`tSetting mapping offline"
        $RangeMappingUpdate = New-Object Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.RangeMappingUpdate
        $RangeMappingUpdate.Status = "Offline"
        $Mapping = $RangeShardMap.UpdateMapping($Mapping, $RangeMappingUpdate)

        Write-Verbose "`tMoving mapping to $ShardLocation"
        $RangeMappingUpdate = New-Object Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.RangeMappingUpdate
        $RangeMappingUpdate.Shard = $InputShard
        $Mapping = $RangeShardMap.UpdateMapping($Mapping, $RangeMappingUpdate)

        Write-Verbose "`tSetting mapping online"
        $RangeMappingUpdate = New-Object Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.RangeMappingUpdate
        $RangeMappingUpdate.Status = "Online"
        $Mapping = $RangeShardMap.UpdateMapping($Mapping, $RangeMappingUpdate)

        $mapping | Out-Mapping
    }
    elseif ($Mappings.count -eq 0)
    {
        throw "`tRange [$RangeLow, $RangeHigh) has no mappings."
    }
    else
    {
        throw "`tRange [$RangeLow, $RangeHigh) is covered by more than one mapping. Mappings found: $($Mappings | Out-Mapping | Format-Table | Out-String)"
    }
}

<#
.SYNOPSIS
    Creates a new ListShardMap<$KeyType>
#>
function New-ListShardMap
{
    # Return a list shard map or null reference if the list shard map does not exist
    param 
    (
         # Type of list shard map
        [parameter(Mandatory=$true)]
        [Type]$KeyType,

        # Shard map manager object      
        [parameter(Mandatory=$true)]
        [System.Object]$ShardMapManager,

        # Name of the list 
        [parameter(Mandatory=$true)]
        [String]$ListShardMapName
    )

    Write-Verbose "Creating List Shard Map"
    
    # Get and cast necessary shard map management methods for a list shard map
    [Type]$ShardMapManagerType = [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManager]
    $CreateListShardMapMethodGeneric = $ShardMapManagerType.GetMethod("CreateListShardMap")
    $CreateListShardMapMethodTyped = $CreateListShardMapMethodGeneric.MakeGenericMethod($KeyType)

    # Create the shard map
    $params = @($ListShardMapName)
    return $CreateListShardMapMethodTyped.Invoke($ShardMapManager, $params)
}

<#
.SYNOPSIS
    Gets a ListShardMap<$KeyType>
#>
function Get-ListShardMap
{
    param 
    (
        # Type of list shard map
        [parameter(Mandatory=$true)]
        [Type]$KeyType,

        # Shard map manager object      
        [parameter(Mandatory=$true)]
        [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManager]$ShardMapManager,

        # Name of the list map 
        [parameter(Mandatory=$true)]
        [String]$ListShardMapName
    )
    
    # Get and cast necessary shard map management methods for a list shard map
    [Type]$ShardMapManagerType = [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMapManager]
    $TryGetListShardMapMethodGeneric = $ShardMapManagerType.GetMethod("TryGetListShardMap")
    $TryGetListShardMapMethodTyped = $TryGetListShardMapMethodGeneric.MakeGenericMethod($KeyType)

    # Check to see if $ShardMapName list shard map exists
    $params = @($ListShardMapName, $null)
    $Exists = $TryGetListShardMapMethodTyped.Invoke($ShardMapManager, $params)
    $ListShardMap = $params[1]

    return $ListShardMap
}

<#
.SYNOPSIS
    Adds a point value for a particular shard to a list shard map
#>
function Add-ListMapping
{
    param 
    (
         # Type of list shard map
        [parameter(Mandatory=$true)]
        [Type]$KeyType,

        [parameter(Mandatory=$true)]
        [System.Object]$ListShardMap,

        [parameter(Mandatory=$true)]
        [object]$ListPoint,

        [parameter(Mandatory=$true)]
        [String]$SqlServerName,

        [parameter(Mandatory=$true)]
        [String]$SqlDatabaseName
    )
      
    # Add new shard location to list shard map
    $ShardLocation = New-Object Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardLocation($SqlServerName, $SqlDatabaseName)

    # Check if the list mapping already exists in the shard map manager    
    $InputShard = $listShardMap.GetShard($ShardLocation)
    $InputPoint = $ListPoint -as $KeyType
    
    Write-Verbose "`tChecking if List Point $ListPoint exists for $SqlDatabaseName..."

    $Mappings = $ListShardMap.GetMappings($InputPoint)

    if($Mappings.count -gt 0 -and $Mappings[0].Value -eq $InputPoint)
    {
        Write-Verbose "`tPoint ($InputPoint) already exists for $SqlDatabaseName"
    }
    else
    {
        Write-Verbose "`tPoint ($InputPoint) for $SqlDatabaseName does not exist, adding..."
        $ShardReference = $listShardMap.CreatePointMapping($InputPoint, $InputShard)
        Write-Verbose "`tNew point ($InputPoint) for $SqlDatabaseName added to list shard map"
    }
}

<#
.SYNOPSIS
    Prints shard name as well as the shard's low and high shard range
#>
function Get-Mappings
{
    param 
    (   # Range map object     
        [parameter(Mandatory=$true)]
        [System.Object]$ShardMap
    )
    
    # Get mappings
    $ShardMap.GetMappings() | Out-Mapping
}

<#
.SYNOPSIS
    Formats the mappings for PowerShell output
#>
function Out-Mapping
{
    param
    (
        [Parameter(Mandatory,ValueFromPipeline)]
        $Mappings
    )

    process {
        $mappings | foreach {
            New-Object -TypeName PSObject -Property @{
                "Status" = $_.Status.ToString();
                "Value" = $_.Value;
                "ShardLocation" = $_.Shard.Location;
            }
        }
    }
}

<#
.SYNOPSIS
    Obtains the list shards for a particular shard map 
#>
function Get-Shards
{
    # Return an array of shards
    [OutputType([System.Object[]])]
    param 
    (
        # Shard map object      
        [parameter(Mandatory=$true)]
        [Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement.ShardMap]$ShardMap
    )

    # Get the list of shards
    return $ShardMap.GetShards()
}
