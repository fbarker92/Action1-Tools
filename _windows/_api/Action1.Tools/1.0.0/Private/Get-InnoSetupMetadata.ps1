function Get-InnoSetupMetadata {
    <#
    .SYNOPSIS
        Extracts metadata from Inno Setup installers.

    .DESCRIPTION
        Detects Inno Setup installers by signature and attempts to extract
        embedded setup information including AppName, AppVersion, AppPublisher.
        Uses binary pattern matching to find the embedded setup script data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Write-Action1Log "Attempting to extract Inno Setup metadata from: $Path" -Level DEBUG

    $result = @{
        Success = $false
        ProductName = $null
        ProductVersion = $null
        Publisher = $null
        InstallerType = $null
        Source = "Inno Setup"
    }

    try {
        # Read the first portion of the file to check for Inno Setup signatures
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $fileContent = [System.Text.Encoding]::ASCII.GetString($bytes[0..([Math]::Min(2MB, $bytes.Length - 1))])

        # Check for Inno Setup signatures
        $isInnoSetup = $false
        $innoSignatures = @(
            'Inno Setup',
            'InnoSetupVersion',
            'Inno Setup Setup Data',
            'inno.exe'
        )

        foreach ($sig in $innoSignatures) {
            if ($fileContent -match [regex]::Escape($sig)) {
                $isInnoSetup = $true
                $result.InstallerType = "Inno Setup"
                break
            }
        }

        if (-not $isInnoSetup) {
            Write-Action1Log "File does not appear to be an Inno Setup installer" -Level DEBUG
            return $result
        }

        Write-Action1Log "Inno Setup signature detected, extracting metadata..." -Level DEBUG

        # Try to find embedded script data patterns
        # Inno Setup stores strings in a specific format, often with null-terminated or length-prefixed strings

        # Look for common Inno Setup script patterns in the binary
        $patterns = @{
            'AppName' = 'AppName=([^\x00\r\n]+)'
            'AppVersion' = 'AppVersion=([^\x00\r\n]+)'
            'AppVerName' = 'AppVerName=([^\x00\r\n]+)'
            'AppPublisher' = 'AppPublisher=([^\x00\r\n]+)'
            'AppPublisherURL' = 'AppPublisherURL=([^\x00\r\n]+)'
            'DefaultDirName' = 'DefaultDirName=([^\x00\r\n]+)'
        }

        $foundValues = @{}
        foreach ($key in $patterns.Keys) {
            if ($fileContent -match $patterns[$key]) {
                $value = $matches[1].Trim()
                # Clean up the value - remove any binary garbage
                $value = $value -replace '[^\x20-\x7E]', ''
                if ($value.Length -gt 0 -and $value.Length -lt 200) {
                    $foundValues[$key] = $value
                }
            }
        }

        # Also try to find version info from common patterns
        if (-not $foundValues['AppVersion']) {
            # Try pattern like "1.2.3" or "v1.2.3" near AppName or version markers
            if ($fileContent -match 'ersion[=:\s]+v?(\d+\.\d+(?:\.\d+)?(?:\.\d+)?)') {
                $foundValues['AppVersion'] = $matches[1]
            }
        }

        if ($foundValues.Count -gt 0) {
            $result.ProductName = $foundValues['AppName']
            $result.ProductVersion = $foundValues['AppVersion']
            $result.Publisher = $foundValues['AppPublisher']

            # AppVerName often contains both name and version
            if (-not $result.ProductName -and $foundValues['AppVerName']) {
                $verName = $foundValues['AppVerName']
                # Try to split "AppName v1.2.3" or "AppName 1.2.3"
                if ($verName -match '^(.+?)\s+v?(\d+\.\d+.*)$') {
                    $result.ProductName = $matches[1]
                    if (-not $result.ProductVersion) {
                        $result.ProductVersion = $matches[2]
                    }
                }
                else {
                    $result.ProductName = $verName
                }
            }

            $result.Success = ($null -ne $result.ProductName -or $null -ne $result.ProductVersion -or $null -ne $result.Publisher)

            Write-Action1Log "Inno Setup metadata extracted" -Level DEBUG -Data $foundValues
        }
    }
    catch {
        Write-Action1Log "Failed to extract Inno Setup metadata" -Level DEBUG -ErrorRecord $_
    }

    return $result
}
