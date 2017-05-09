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
            if (!$NoEcho)
            {            
                Write-Output "Signed-in as $($AzureContext.Account), Subscription '$($AzureContext.Subscription.SubscriptionId)' '$($AzureContext.Subscription.SubscriptionName)'"
                Write-Verbose $AzureContext
            }
            return
        }
        catch
        {
            # Fall through and require login 
        }         
    }  
    #Login to Azure 
    Login-AzureRmAccount
    $Azurecontext = Get-AzureRmContext
    Write-Output "You are signed-in as: $($Azurecontext.Account)"

    # Get subscription list 
    $subscriptionList = Get-AzureRmSubscription
    if($subscriptionList.Length -lt 1)
    {
        Write-Error "Your Azure account does not have any active subscriptions. Exiting..."
        exit 
    }
    elseif($subscriptionList.Length -eq 1)
    {
        Select-AzureRmSubscription -SubscriptionId $subscriptionList[0].SubscriptionId > $null
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
        $subscriptionList | Format-Table Row,SubscriptionId,SubscriptionName -AutoSize
            
        # Select single Azure subscription for session 
        try
        {
            [int]$selectedRow = Read-Host "Enter the row number to select the subscription to use" -ErrorAction Stop

            $context = Select-AzureRmSubscription -SubscriptionId $subscriptionList[($selectedRow - 1)] -ErrorAction Stop

            Write-Output "Subscription Id '$($context.Subscription.SubscriptionId)' selected."
        }
        catch
        { 
            Write-Error 'Invalid selection. Exiting...'
            exit 
        }
    }
}