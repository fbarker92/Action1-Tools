function Get-NsisMetadata {
    <#
    .SYNOPSIS
        Extracts metadata from NSIS (Nullsoft Scriptable Install System) installers.

    .DESCRIPTION
        Detects NSIS installers by signature and attempts to extract
        embedded metadata including product name, version, and publisher.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Write-Action1Log "Attempting to extract NSIS metadata from: $Path" -Level DEBUG

    $result = @{
        Success = $false
        ProductName = $null
        ProductVersion = $null
        Publisher = $null
        InstallerType = $null
        Source = "NSIS"
    }

    try {
        # Read the file content
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $fileContent = [System.Text.Encoding]::ASCII.GetString($bytes[0..([Math]::Min(2MB, $bytes.Length - 1))])

        # Check for NSIS signatures
        $isNsis = $false
        $nsisSignatures = @(
            'NullsoftInst',
            'Nullsoft Install System',
            'NSIS Error',
            'nsis.sf.net'
        )

        foreach ($sig in $nsisSignatures) {
            if ($fileContent -match [regex]::Escape($sig)) {
                $isNsis = $true
                $result.InstallerType = "NSIS"
                break
            }
        }

        if (-not $isNsis) {
            Write-Action1Log "File does not appear to be an NSIS installer" -Level DEBUG
            return $result
        }

        Write-Action1Log "NSIS signature detected, extracting metadata..." -Level DEBUG

        # NSIS installers often have strings embedded that we can extract
        # Look for common patterns

        # Try to find Name and Version from NSIS script defines
        # NSIS uses !define statements which may be embedded

        $patterns = @{
            'PRODUCT_NAME' = '(?:PRODUCT_NAME|APP_NAME|NAME)[="\s]+([^\x00\r\n"]+)'
            'PRODUCT_VERSION' = '(?:PRODUCT_VERSION|APP_VERSION|VERSION)[="\s]+v?([0-9][^\x00\r\n"]*)'
            'PRODUCT_PUBLISHER' = '(?:PRODUCT_PUBLISHER|PUBLISHER|COMPANY)[="\s]+([^\x00\r\n"]+)'
        }

        $foundValues = @{}
        foreach ($key in $patterns.Keys) {
            if ($fileContent -match $patterns[$key]) {
                $value = $matches[1].Trim().Trim('"')
                $value = $value -replace '[^\x20-\x7E]', ''
                if ($value.Length -gt 0 -and $value.Length -lt 200) {
                    $foundValues[$key] = $value
                }
            }
        }

        # Also look for branding text which often contains product info
        if ($fileContent -match 'Nullsoft Install System v[\d.]+') {
            # Try to find the installer title near the beginning
            if ($fileContent -match '(?<=\x00)([A-Za-z][A-Za-z0-9\s\-_.]+(?:Setup|Install(?:er)?|v?\d+\.\d+)[A-Za-z0-9\s\-_.]*?)(?=\x00)') {
                $potentialName = $matches[1].Trim()
                if ($potentialName.Length -gt 3 -and $potentialName.Length -lt 100 -and -not $foundValues['PRODUCT_NAME']) {
                    $foundValues['PRODUCT_NAME'] = $potentialName -replace '\s*(Setup|Installer?)$', ''
                }
            }
        }

        if ($foundValues.Count -gt 0) {
            $result.ProductName = $foundValues['PRODUCT_NAME']
            $result.ProductVersion = $foundValues['PRODUCT_VERSION']
            $result.Publisher = $foundValues['PRODUCT_PUBLISHER']
            $result.Success = ($null -ne $result.ProductName -or $null -ne $result.ProductVersion -or $null -ne $result.Publisher)

            Write-Action1Log "NSIS metadata extracted" -Level DEBUG -Data $foundValues
        }
    }
    catch {
        Write-Action1Log "Failed to extract NSIS metadata" -Level DEBUG -ErrorRecord $_
    }

    return $result
}
