<#
.SYNOPSIS
    Returns the User name and resource group name used during the Wingtip SaaS application deployment.  
    The values defined here are referenced by the learning module scripts.
#>


## Update the two variables below to the values used when the Wingtip SaaS app was deployed.   

$ResourceGroupName = "<resourcegroup>" # the resource group used when the Wingtip SaaS application was deployed. CASE SENSITIVE
$User              = "<user>"         # the User value entered when the Wingtip SaaS application was deployed

##  DO NOT CHANGE VALUES BELOW HERE -------------------------------------------------------------

function Get-UserConfig {

    $userConfig = @{`
        ResourceGroupName = $ResourceGroupName     
        Name =              $User.ToLower()   
    }
   
    if ($userConfig.ResourceGroupName -eq "<resourcegroup>" -or $userConfig.Name -eq "<user>")
    {
        throw 'UserConfig is not set.  Modify $ResourceGroupName and $User in UserConfig.psm1 and try again.'
    }

    return $userConfig

}
