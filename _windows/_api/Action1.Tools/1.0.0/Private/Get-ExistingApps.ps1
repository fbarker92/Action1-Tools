function Get-ExistingApps {
    <#
    .SYNOPSIS
        Gets list of existing app display names under a vendor for auto-completion.
    .DESCRIPTION
        Scans app folders and reads the AppName field from manifest files
        to return the display name (with spaces/punctuation) instead of folder names.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$Vendor
    )

    $vendorPath = Join-Path $BasePath $Vendor
    if (Test-Path $vendorPath) {
        $appFolders = Get-ChildItem -Path $vendorPath -Directory -ErrorAction SilentlyContinue
        $apps = @{}

        foreach ($appFolder in $appFolders) {
            # Look for any manifest in app/version/manifest.json
            $manifests = Get-ChildItem -Path $appFolder.FullName -Recurse -Filter "manifest.json" -ErrorAction SilentlyContinue | Select-Object -First 1

            if ($manifests) {
                try {
                    $manifest = Get-Content -Path $manifests.FullName -Raw | ConvertFrom-Json
                    if ($manifest.AppName) {
                        $apps[$manifest.AppName] = $true
                    }
                }
                catch {
                    # Fall back to folder name if manifest can't be read
                    $apps[$appFolder.Name] = $true
                }
            }
            else {
                # No manifest found, use folder name
                $apps[$appFolder.Name] = $true
            }
        }

        $apps.Keys | Sort-Object
    }
}
