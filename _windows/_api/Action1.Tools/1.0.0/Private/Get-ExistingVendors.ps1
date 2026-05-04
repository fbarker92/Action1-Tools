function Get-ExistingVendors {
    <#
    .SYNOPSIS
        Gets list of existing vendor display names for auto-completion.
    .DESCRIPTION
        Scans vendor folders and reads the Publisher field from manifest files
        to return the display name (with spaces/punctuation) instead of folder names.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$BasePath = (Get-Location).Path
    )

    if (Test-Path $BasePath) {
        $vendorFolders = Get-ChildItem -Path $BasePath -Directory -ErrorAction SilentlyContinue
        $vendors = @{}

        foreach ($vendorFolder in $vendorFolders) {
            # Look for any manifest in vendor/app/version/manifest.json
            $manifests = Get-ChildItem -Path $vendorFolder.FullName -Recurse -Filter "manifest.json" -ErrorAction SilentlyContinue | Select-Object -First 1

            if ($manifests) {
                try {
                    $manifest = Get-Content -Path $manifests.FullName -Raw | ConvertFrom-Json
                    if ($manifest.Publisher) {
                        $vendors[$manifest.Publisher] = $true
                    }
                }
                catch {
                    # Fall back to folder name if manifest can't be read
                    $vendors[$vendorFolder.Name] = $true
                }
            }
            else {
                # No manifest found, use folder name
                $vendors[$vendorFolder.Name] = $true
            }
        }

        $vendors.Keys | Sort-Object
    }
}
