function Get-ExistingVersions {
    <#
    .SYNOPSIS
        Gets list of existing version folders under an app for auto-completion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$Vendor,

        [Parameter(Mandatory)]
        [string]$AppName
    )

    $appPath = Join-Path $BasePath $Vendor $AppName
    if (Test-Path $appPath) {
        Get-ChildItem -Path $appPath -Directory -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Name
    }
}
