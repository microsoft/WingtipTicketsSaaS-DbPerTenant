<#
.SYNOPSIS
    Intiializes and formats the output of jobs used in the recovery and repatriation scripts
#>

function Format-JobOutput
{
   param (
    [parameter(Mandatory=$true)]
    [AllowEmptyString()]
    [string] $JobOutput
    )

    $formattedJobOutput = $null

    if (!$JobOutput)
    {
        $formattedJobOutput = '--'
    }
    elseif ($JobOutput.Count -gt 1)
    {
       # Display most recent job status 
       $formattedJobOutput = $JobOutput[-1]
    }

    return $formattedJobOutput
}
