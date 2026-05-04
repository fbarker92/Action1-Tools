function Get-Action1Interactive {
    <#
    .SYNOPSIS
        Gets the current interactive mode setting.

    .DESCRIPTION
        Returns whether the module will prompt for missing required values.

    .EXAMPLE
        Get-Action1Interactive
        # Returns $true or $false

    .EXAMPLE
        if (Get-Action1Interactive) { Write-Host "Prompts enabled" }
    #>
    [CmdletBinding()]
    param()

    return $script:Interactive
}
