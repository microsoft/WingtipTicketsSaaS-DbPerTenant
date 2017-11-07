<#
.SYNOPSIS
    Returns the User name and resource group name used during the WTP application deployment.  
    The values defined here are referenced by the learning module scripts.
#>

function Get-UserConfig {

    $userConfig = @{`
        ResourceGroupName = "wtp-bgc"    # the resource group used when the WTP application was deployed. CASE SENSITIVE
        Name =              "bgc"             # the User name entered when the WTP application was deployed  
    }

    if ($userConfig.ResourceGroupName -eq "<resourcegroup>" -or $userConfig.Name -eq "<user>")
    {
        throw '$userConfig.ResourceGroupName and $userConfig.Name are not set.  Modify both values in UserConfig.psm1 and try again.'
    }

    return $userConfig

}
