<#
.SYNOPSIS
    If not currently logged in to Azure, prompts for login and selection of subscription to use. 
#>
function Initialize-Subscription
{
    param(
        # Force requires the user selects a subscription explicitly 
        [parameter(Mandatory=$false)]
        [switch] $Force,

        # NoEcho stops the output of the signed in user to prevent double echo  
        [parameter(Mandatory=$false)]
        [switch] $NoEcho
    )

    If(!$Force) 
    {
        try 
        {
            # Use previous login credentials if already logged in 
            $AzureContext = Get-AzureRmContext
            
            if (!$AzureContext.Account)
            {
                # Fall through and require login   
            }
            else
            {             
                # Don't display subscription details if already logged in
                if (!$NoEcho)
                {            
                    $subscriptionId = Get-SubscriptionId
                    $subscriptionName = Get-SubscriptionName
                    Write-Output "Signed-in as $($AzureContext.Account), Subscription '$($subscriptionId)' '$($subscriptionName)'"
                    Write-Verbose $AzureContext
                }
                return
            }
            
        }
        catch
        {
            # Fall through and require login - (Get-AzureRmContext fails with AzureRM modules < 4.0 if there is no logged in acount)
        }         
    }  
    #Login to Azure 
    Login-AzureRmAccount
    $Azurecontext = Get-AzureRmContext
    Write-Output "You are signed-in as: $($Azurecontext.Account)"

    # Get subscription list 
    $subscriptionList = Get-SubscriptionList
    if($subscriptionList.Length -lt 1)
    {
        Write-Error "Your Azure account does not have any active subscriptions. Exiting..."
        exit 
    }
    elseif($subscriptionList.Length -eq 1)
    {
        Select-AzureRmSubscription -SubscriptionId $subscriptionList[0].Id > $null
    }
    elseif($subscriptionList.Length -gt 1)
    {
        # Display available subscriptions 
        $index = 1
        foreach($subscription in $subscriptionList)
        {
            $subscription | Add-Member -type NoteProperty -name "Row" -value $index
            $index++
        }

        # Prompt for selection 
        Write-Output "Your Azure subcriptions: "
        $subscriptionList | Format-Table Row, Id, Name -AutoSize
                    
        # Select single Azure subscription for session 
        try
        {
            [int]$selectedRow = Read-Host "Enter the row number to select the subscription to use" -ErrorAction Stop

            Select-AzureRmSubscription -SubscriptionId $subscriptionList[($selectedRow - 1)] -ErrorAction Stop > $null

            Write-Output "Subscription Id '$($subscriptionList[($selectedRow - 1)].Id)' selected."
        }
        catch
        { 
            Write-Error 'Invalid selection. Exiting...'
            exit 
        }
    }
}

function Get-SubscriptionId
{
    $Azurecontext = Get-AzureRmContext
    $AzureModuleVersion = Get-Module AzureRM.Resources -list

    # Check PowerShell version to accomodate breaking change in AzureRM modules greater than 4.0
    if ($AzureModuleVersion.Version.Major -ge 4)
    {
        return $Azurecontext.Subscription.Id
    }
    else
    {
        return $Azurecontext.Subscription.SubscriptionId
    }
}

function Get-SubscriptionName
{
    $Azurecontext = Get-AzureRmContext
    $AzureModuleVersion = Get-Module AzureRM.Resources -list 

    # Check PowerShell version to accomodate breaking change in AzureRM modules greater than 4.0
    if ($AzureModuleVersion.Version.Major -ge 4)
    {
        return $Azurecontext.Subscription.Name
    }
    else
    {
        return $Azurecontext.Subscription.SubscriptionName
    }
}

function Get-SubscriptionList
{
    $AzureModuleVersion = Get-Module AzureRM.Resources -list

    # Check PowerShell version to accomodate breaking change in AzureRM modules greater than 4.0
    if ($AzureModuleVersion.Version.Major -ge 4)
    {
        return Get-AzureRmSubscription
    }
    else
    {
        # Add 'id' and 'name' properties to subscription object returned for AzureRM modules less than 4.0
        $subscriptionObject = Get-AzureRmSubscription
        
        foreach ($subscription in $subscriptionObject)
        {
            $subscription | Add-Member -type NoteProperty -name "Id" -Value $($subscription.SubscriptionId)
            $subscription | Add-Member -type NoteProperty -Name "Name" -Value $($subscription.SubscriptionName) 
        }
        
        return $subscriptionObject 
    }   
}

function Get-TenantId
{
    $Azurecontext = Get-AzureRmContext
    $AzureModuleVersion = Get-Module AzureRM.Resources -list 

    # Check PowerShell version to accomodate breaking change in AzureRM modules greater than 4.0
    if ($AzureModuleVersion.Version.Major -ge 4)
    {
        return $Azurecontext.Tenant.Id
    }
    else
    {
        return $Azurecontext.Tenant.TenantId
    }
}
