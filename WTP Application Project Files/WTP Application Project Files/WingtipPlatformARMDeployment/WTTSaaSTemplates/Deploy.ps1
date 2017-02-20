<#
	.Synopsis
	Wingtip Tickets Platform (WTP) Demo Environment.
	.DESCRIPTION
	This script is used to create a new Wingtip Tickets Platform (WTP) Demo Environment.
	Update the paramenters in the DeployWingTipSaaS.parameters.json file.
	.EXAMPLE
	Deploy -resourceGroupLocation <Azure Location>
#>

[CmdletBinding()]
param(
	
	[string]
	$resourceGroupLocation,

	[string]
	$user
)
## This function initializes the subscription and lists available subscriptions to select from
function InitSubscription{
       
    #login
    Add-AzureRmAccount -WarningAction SilentlyContinue | out-null
    $account = Get-AzureRmContext
	
    Write-Host "You are signed-in with: " -NoNewline
    Write-Host $account.Account.Id

 	$subList = Get-AzureRmSubscription
	if($subList.Length -lt 1){
		throw 'Your azure account does not have any subscriptions.  A subscription is required to run this tool'
	} 

	$subCount = 0
	foreach($sub in $subList){
		$subCount++
		$sub | Add-Member -type NoteProperty -name RowNumber -value $subCount
	}

	if($subCount -gt 1)
	{
		Write-Host "Your Azure Subscriptions: " -NoNewline
		
		$subList | Format-Table RowNumber,SubscriptionId,SubscriptionName -AutoSize
		$rowNum = Read-Host 'Enter the row number (1 -'$subCount') of a subscription'

		while( ([int]$rowNum -lt 1) -or ([int]$rowNum -gt [int]$subCount)){
			Write-Host "Invalid subscription row number. Please enter a row number from the list above" -NoNewline
			$rowNum = Read-Host 'Enter subscription row number'
		}
	}
	else{
		$rowNum = 1
	}
	
	$global:subscriptionID = $subList[$rowNum-1].SubscriptionId;
	
#switch to appropriate subscription 
    try{ 
        Select-AzureRmSubscription -SubscriptionId $global:subscriptionID 
    }  
    catch{ 
        throw 'Subscription ID provided is invalid: ' + $global:subscriptionID     
    } 

}
## Variables
$path = (Get-Item -Path ".\" -Verbose).FullName + "\Templates"
$resourceGroupName = "Wingtip-"+$user
$DeployWingTipSaaSTemplateFile = "$path\azuredeploy.json"
$DeployWingTipSaaSParameterFile = "$path\azuredeploy.parameters.json"

## Initialize the Azure Subscription function
InitSubscription

## Register needed Azure Resource Providers
$resourceProviders = @("microsoft.sql", "microsoft.web");
if($resourceProviders.length) {
    Write-Host "Registering resource providers"
    foreach($resourceProvider in $resourceProviders) {
        Register-AzureRmResourceProvider -ProviderNamespace $resourceProvider;
    }
}

#Create or check for existing resource group
$resourceGroup = Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if(!$resourceGroup)
{
    Write-Host "Resource group '$resourceGroupName' does not exist. To create a new resource group, please enter a location.";
    if(!$resourceGroupLocation) {
        $resourceGroupLocation = Read-Host "resourceGroupLocation";
    }
    Write-Host "Creating resource group '$resourceGroupName' in location '$resourceGroupLocation'";
    New-AzureRmResourceGroup -Name $resourceGroupName -Location $resourceGroupLocation
}
else{
    Write-Host "Using existing resource group '$resourceGroupName'";
}

# create tenant database by template
$starttime = $(Get-Date)
if(Test-Path $DeployWingTipSaaSTemplateFile)
{
	New-AzureRmResourceGroupDeployment -TemplateFile $DeployWingTipSaaSTemplateFile -user $user -ResourceGroupName $ResourceGroupName
}
else
{
	Write-Host "Unable to locate $DeployWingTipSaaSTemplateFile"
}
Write-Output (New-TimeSpan $starttime $(Get-Date)).TotalSeconds