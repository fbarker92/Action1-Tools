function Get-InstallerMetadata {
    <#
    .SYNOPSIS
        Comprehensive metadata extraction from installer files with multiple fallback methods.

    .DESCRIPTION
        Attempts to extract metadata from installers using multiple techniques:
        1. MSI database querying (for .msi files)
        2. PE file version information
        3. Digital signature certificate parsing
        4. Inno Setup script extraction
        5. NSIS installer detection and extraction

        Results are merged with priority given to more reliable sources.

    .PARAMETER Path
        Path to the installer file (.exe or .msi)

    .EXAMPLE
        $metadata = Get-InstallerMetadata -Path "C:\Downloads\setup.exe"
        Write-Host "Product: $($metadata.ProductName) v$($metadata.ProductVersion) by $($metadata.Publisher)"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Installer file not found: $Path"
    }

    $installerFile = Get-Item $Path
    $extension = $installerFile.Extension.ToLower()

    Write-Action1Log "Starting comprehensive metadata extraction for: $($installerFile.Name)" -Level INFO

    # Initialize result with defaults
    $result = @{
        ProductName = $null
        ProductVersion = $null
        Publisher = $null
        Description = $null
        InstallerType = $null
        Sources = @()
        AllMetadata = @{}
    }

    # Collection of all extraction results for debugging/logging
    $extractionResults = @()

    # 1. MSI Database (highest priority for MSI files)
    if ($extension -eq '.msi') {
        Write-Host "  Querying MSI database..." -ForegroundColor Gray
        $msiResult = Get-MsiMetadata -Path $Path
        $extractionResults += $msiResult
        $result.AllMetadata['MSI'] = $msiResult

        if ($msiResult.Success) {
            $result.Sources += "MSI Database"
            if (-not $result.ProductName -and $msiResult.ProductName) { $result.ProductName = $msiResult.ProductName }
            if (-not $result.ProductVersion -and $msiResult.ProductVersion) { $result.ProductVersion = $msiResult.ProductVersion }
            if (-not $result.Publisher -and $msiResult.Manufacturer) { $result.Publisher = $msiResult.Manufacturer }
            if (-not $result.Description -and $msiResult.Description) { $result.Description = $msiResult.Description }
            $result.InstallerType = "MSI"
        }
    }

    # 2. File Version Info (works for both EXE and MSI)
    Write-Host "  Reading file version information..." -ForegroundColor Gray
    $versionResult = Get-FileVersionMetadata -Path $Path
    $extractionResults += $versionResult
    $result.AllMetadata['FileVersion'] = $versionResult

    if ($versionResult.Success) {
        $result.Sources += "File Version Info"
        if (-not $result.ProductName -and $versionResult.ProductName) { $result.ProductName = $versionResult.ProductName }
        if (-not $result.ProductVersion -and $versionResult.ProductVersion) { $result.ProductVersion = $versionResult.ProductVersion }
        if (-not $result.ProductVersion -and $versionResult.FileVersion) { $result.ProductVersion = $versionResult.FileVersion }
        if (-not $result.Publisher -and $versionResult.Publisher) { $result.Publisher = $versionResult.Publisher }
        if (-not $result.Description -and $versionResult.Description) { $result.Description = $versionResult.Description }
    }

    # 3. Digital Signature (good for publisher info)
    Write-Host "  Checking digital signature..." -ForegroundColor Gray
    $sigResult = Get-DigitalSignatureMetadata -Path $Path
    $extractionResults += $sigResult
    $result.AllMetadata['DigitalSignature'] = $sigResult

    if ($sigResult.Success) {
        $result.Sources += "Digital Signature"
        # Only use signature for publisher if we don't have one yet
        if (-not $result.Publisher -and $sigResult.Publisher) { $result.Publisher = $sigResult.Publisher }
    }

    # 4. Inno Setup detection and extraction (for EXE files)
    if ($extension -eq '.exe') {
        Write-Host "  Checking for Inno Setup installer..." -ForegroundColor Gray
        $innoResult = Get-InnoSetupMetadata -Path $Path
        $extractionResults += $innoResult
        $result.AllMetadata['InnoSetup'] = $innoResult

        if ($innoResult.Success) {
            $result.Sources += "Inno Setup"
            $result.InstallerType = "Inno Setup"
            if (-not $result.ProductName -and $innoResult.ProductName) { $result.ProductName = $innoResult.ProductName }
            if (-not $result.ProductVersion -and $innoResult.ProductVersion) { $result.ProductVersion = $innoResult.ProductVersion }
            if (-not $result.Publisher -and $innoResult.Publisher) { $result.Publisher = $innoResult.Publisher }
        }

        # 5. NSIS detection and extraction (for EXE files, if not Inno)
        if (-not $innoResult.Success -or -not $result.InstallerType) {
            Write-Host "  Checking for NSIS installer..." -ForegroundColor Gray
            $nsisResult = Get-NsisMetadata -Path $Path
            $extractionResults += $nsisResult
            $result.AllMetadata['NSIS'] = $nsisResult

            if ($nsisResult.Success) {
                $result.Sources += "NSIS"
                if (-not $result.InstallerType) { $result.InstallerType = "NSIS" }
                if (-not $result.ProductName -and $nsisResult.ProductName) { $result.ProductName = $nsisResult.ProductName }
                if (-not $result.ProductVersion -and $nsisResult.ProductVersion) { $result.ProductVersion = $nsisResult.ProductVersion }
                if (-not $result.Publisher -and $nsisResult.Publisher) { $result.Publisher = $nsisResult.Publisher }
            }
        }
    }

    # Set default installer type if not detected
    if (-not $result.InstallerType) {
        $result.InstallerType = switch ($extension) {
            '.msi' { 'MSI' }
            '.exe' { 'EXE' }
            default { 'Unknown' }
        }
    }

    # Apply final fallbacks
    if (-not $result.ProductName) {
        $result.ProductName = [System.IO.Path]::GetFileNameWithoutExtension($installerFile.Name)
        $result.Sources += "Filename (fallback)"
    }
    if (-not $result.ProductVersion) {
        $result.ProductVersion = "1.0.0"
        $result.Sources += "Default version (fallback)"
    }
    if (-not $result.Publisher) {
        $result.Publisher = "Unknown"
    }

    Write-Action1Log "Metadata extraction complete" -Level INFO -Data @{
        ProductName = $result.ProductName
        ProductVersion = $result.ProductVersion
        Publisher = $result.Publisher
        InstallerType = $result.InstallerType
        Sources = $result.Sources -join ', '
    }

    return $result
}
