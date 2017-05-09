[cmdletbinding()]

<#
 .SYNOPSIS
    Enables diagnostics for the WTP application.

 .DESCRIPTION
    Enables diagnostics collection for the elastic pools and databases in the WTP application. Requires
    the Operational Insights Workspace is deployed first.

 .PARAMETER WtpResourceGroupName
    The name of the resource group in which the WTP application is deployed.

 .PARAMETER WtpUser
    # The 'User' value entered during the deployment of the WTP application.

 .PARAMETER WtpUser
    # Update switch will cause diagnostic settings for individual settings to be updated to emit to an additional workspace.
#>
param
(
    [Parameter(Mandatory=$True)]
    [string] $WtpResourceGroupName,

    [Parameter(Mandatory=$True)]
    [string]$WtpUser,

    [switch]$Update
)

Import-Module $PSScriptRoot\..\..\Common\SubscriptionManagement -Force
Import-Module $PSScriptRoot\..\..\WtpConfig -Force
Import-Module AzureRm.OperationalInsights 


# Get Azure credentials if not already logged on 
Initialize-Subscription

$config = Get-Configuration

<#
 .SYNOPSIS    
    Enable Diagnostics gathering in an Operational Insights workspace for a set of resources
#>
function Enable-DiagnosticsForResources
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$True)]
        [array]$Resources,
        
        [Parameter(Mandatory=$True)]
        [String]$WorkspaceId,
        
        [switch]$Update
    )


    Foreach($Resource in $Resources)
    {
        try
        {            
            $ResourceDiagnosticSetting = get-AzureRmDiagnosticSetting -ResourceId $Resource.ResourceId
           
            if($ResourceDiagnosticSetting.Metrics.Enabled -eq $False)
            {
                Set-AzureRmDiagnosticSetting -WorkspaceId $WorkspaceId -ResourceId $Resource.ResourceId -Enabled $True
                Write-Verbose "Diagnostics enabled for resource $($Resource.Name) of type [$($Resource.ResourceType)]"
            }
            ElseIf($ResourceDiagnosticSetting.Metrics.Enabled -eq $True -and $ResourceDiagnosticSetting.WorkspaceId -eq $null)
            {
                Set-AzureRmDiagnosticSetting -WorkspaceId $WorkspaceId -ResourceId $Resource.ResourceId
                    Write-Verbose "Added workspace for resource $($Resource.Name) of type [$($Resource.ResourceType)]"
            }
            elseif($Update -eq $True)
            {
                Set-AzureRmDiagnosticSetting -WorkspaceId $WorkspaceId -ResourceId $Resource.ResourceId -Enabled $True
                    Write-Verbose "Updated the workspace for resource $($Resource.Name) of type [$($Resource.ResourceType)]" 
            }
            else
            {
                    Write-Verbose "No change required for resource $($Resource.Name) of type [$($Resource.ResourceType)]"
            }
        }
        catch
        {
            Write-Error $_.Exception.Message -ErrorAction Continue
            Write-Error "Error enabling diagnostics for $Resource"
        }
    }


}

# Main Script ------------------------------------------------------------------------------------------------------------------

# Set up the Operational Insights workspace name 
$workspaceName = $config.LogAnalyticsWorkspaceNameStem + $WtpUser

# Get the workspace 
$workspace = Get-AzureRmOperationalInsightsWorkspace `
    -ResourceGroupName $WtpResourceGroupname `
    -Name $WorkspaceName `
    -ErrorAction SilentlyContinue

if(!$workspace)
{
    Write-Output "Log Analytics workspace with name '$WorkspaceName' not found.  Exiting..."
    exit
}

# Get the current subscription
$azureContext = Get-AzureRmContext
$subscriptionId = $azureContext.Subscription.SubscriptionId

$WorkspaceId = "/subscriptions/$subscriptionId/resourcegroups/$WtpResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName"

# Define the resource types for which diagnostics will be enabled
$resourceTypes = ("Microsoft.Sql/servers/elasticpools","Microsoft.Sql/servers/databases")

# Enable diagnostic logging for all resources of each type in the WTP resource group 
foreach($resourceType in $resourceTypes)
{
    $resources = Get-AzureRmResource -ResourceGroupName $WtpResourceGroupName -ResourceType $resourceType 
    
    if ($resources)
    {
        Write-Output "Enabling or checking diagnostic logging for $($resources.Count) $resourceType."

        if ($Update.IsPresent)
        {
            Enable-DiagnosticsForResources `
                -Resources $Resources `
                -WorkspaceId $WorkspaceId `
                -Update `
                -Verbose > $null
        }
        else
        {
            Enable-DiagnosticsForResources `
                -Resources $Resources `
                -WorkspaceId $WorkspaceId `
                -Verbose > $null
        }
    }
    else
    {
        Write-Output "No resources found in resource group '$WtpResourceGroupName' of type '$resourceType'."
    }
}

Write-Output "Diagnostics enablement complete."