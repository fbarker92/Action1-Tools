function Set-Action1Interactive {
    <#
    .SYNOPSIS
        Sets whether the module uses interactive prompts.

    .DESCRIPTION
        When enabled (default), the module will prompt for missing required values
        such as organization selection, credentials, etc.
        When disabled, functions will fail if required values are not provided.

    .PARAMETER Enabled
        $true to enable interactive prompts, $false to disable.

    .EXAMPLE
        Set-Action1Interactive -Enabled $true
        # Enables interactive prompts (default behavior)

    .EXAMPLE
        Set-Action1Interactive -Enabled $false
        # Disables prompts - useful for scripting/automation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$Enabled
    )

    $script:Interactive = $Enabled

    if ($Enabled) {
        Write-Host "Interactive mode enabled - will prompt for missing values" -ForegroundColor Green
    } else {
        Write-Host "Interactive mode disabled - functions will fail if required values not provided" -ForegroundColor Yellow
    }
}
