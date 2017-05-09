# Helper script for invoking Apply-SQLCommandToTenantDatabases.
# Crude way to apply a one-time script against tenant dbs in catalog.  Use Elastic Jobs for any serious work...! 

# SQL script to be applied.  Uses Invoke-SqlCmd so can include batches with GO statements.  
# Script should be idempotent as will retry on error. No results are returned, check dbs for success.  
$commandText = " 
    -- Add script to be deployed here  
    "
    
# query timeout in seconds
$queryTimeout = 60

## ------------------------------------------------------------------------------------------------ 

Import-Module "$PSScriptRoot\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\UserConfig" -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription -NoEcho

# Get the resource group and user names used when the WTP application was deployed from UserConfig.psm1.  
$wtpUser = Get-UserConfig
 
& $PSScriptRoot\Invoke-SqlCmdOnTenantDatabases `
    -WtpResourceGroupName $wtpUser.ResourceGroupName `
    -WtpUser $wtpUser.Name `
    -CommandText $commandText `
    -QueryTimeout $queryTimeout
