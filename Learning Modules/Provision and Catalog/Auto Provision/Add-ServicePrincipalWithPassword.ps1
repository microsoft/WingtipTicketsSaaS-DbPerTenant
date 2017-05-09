<#
.SYNOPSIS
    Creates an identity for an application, and assigns it an RBAC role in a specified scope.
#>
Param (

 # Use to set scope to resource group. If no value is provided, scope is set to subscription.
 [Parameter(Mandatory=$false)]
 [String] $ResourceGroup,

 # Use to set subscription. If no value is provided, default subscription is used. 
 [String] $SubscriptionId,

 [Parameter(Mandatory=$true)]
 [String] $ApplicationName,

 [Parameter(Mandatory=$true)]
 [String] $Password,

 [ValidateSet("contributor","reader")]
 [String] $RbacRole = "reader"
 )

Import-Module AzureRM.Resources
Import-Module "$PSScriptRoot\..\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\..\WtpConfig" -Force
Import-Module "$PSScriptRoot\..\..\UserConfig" -Force

# Get Azure credentials if not already logged on.
Initialize-Subscription

if ($SubscriptionId -eq "") 
{
$SubscriptionId = (Get-AzureRmContext).Subscription.SubscriptionId
}
else
{
Set-AzureRmContext -SubscriptionId $SubscriptionId
}

if ($ResourceGroup -eq "")
{
$Scope = "/subscriptions/" + $SubscriptionId
}
else
{
$Scope = (Get-AzureRmResourceGroup -Name $ResourceGroup -ErrorAction Stop).ResourceId
}

$Application = Get-AzureRmADApplication -IdentifierUri  ("http://" + $ApplicationName)

if(!$Application)
{
    # Create Active Directory application with password
     $Application = New-AzureRmADApplication `
                        -DisplayName $ApplicationName `
                        -HomePage ("http://" + $ApplicationName + ".azurewebsites.net") `
                        -IdentifierUris ("http://" + $ApplicationName) `
                        -Password $Password
}

$ServicePrincipal = Get-AzureRmADServicePrincipal -SearchString $ApplicationName

if (!$ServicePrincipal) 
{
    # Create Service Principal for the AD app
    $ServicePrincipal = New-AzureRmADServicePrincipal -ApplicationId $Application.ApplicationId 
} 
 
# check if the role assignment exists
$NewRole = Get-AzureRmRoleAssignment -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
$Retries = 0;
While ($NewRole -eq $null -and $Retries -le 9)
{
# Sleep here for a few seconds to allow the service principal application to become active (should only take a couple of seconds normally)
Sleep 10

New-AzureRmRoleAssignment `
    -RoleDefinitionName $RbacRole `
    -ServicePrincipalName $Application.ApplicationId `
    -Scope $Scope `
    -ErrorAction SilentlyContinue `
    | Write-Verbose 
    
$NewRole = Get-AzureRmRoleAssignment -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
    
$Retries++;
}
 
Write-Output "Service principal '$($ServicePrincipal.DisplayName)' exists or was created for app id '$($Application.ApplicationId)'"
