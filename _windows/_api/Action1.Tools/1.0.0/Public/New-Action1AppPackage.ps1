function New-Action1AppPackage {
    <#
    .SYNOPSIS
        Creates a new Action1 application package with support for multiple architectures.

    .DESCRIPTION
        Prompts for application metadata and creates the package folder structure
        in /vendor/app/version/ format. Supports adding installers for multiple
        architectures (x86, x64, arm64).

    .PARAMETER BasePath
        Base path where the package folder structure will be created.
        Defaults to current directory.

    .PARAMETER Publisher
        Publisher/vendor name. If not provided, will prompt.

    .PARAMETER AppName
        Application name. If not provided, will prompt.

    .PARAMETER Version
        Application version. If not provided, will prompt.

    .PARAMETER Description
        Application description. Optional.

    .EXAMPLE
        New-Action1AppPackage
        # Interactive mode - prompts for all information

    .EXAMPLE
        New-Action1AppPackage -Publisher "Microsoft" -AppName "PowerShell" -Version "7.4.0"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$BasePath = (Get-Location).Path,

        [Parameter()]
        [string]$Publisher,

        [Parameter()]
        [string]$AppName,

        [Parameter()]
        [string]$Version,

        [Parameter()]
        [string]$Description
    )

    Write-Host "`n=== Action1 Application Packager ===" -ForegroundColor Cyan
    Write-Action1Log "Creating new application package" -Level INFO

    # Get existing folders for auto-completion
    $existingVendors = @(Get-ExistingVendors -BasePath $BasePath)

    # Prompt for application information
    Write-Host "`n--- Application Information ---" -ForegroundColor Cyan

    if (-not $Publisher) {
        $Publisher = Read-HostWithCompletion `
            -Prompt "Vendor/Publisher" `
            -Suggestions $existingVendors `
            -Required
    }

    $sanitizedVendorForLookup = $Publisher -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
    $existingApps = @(Get-ExistingApps -BasePath $BasePath -Vendor $sanitizedVendorForLookup)

    if (-not $AppName) {
        $AppName = Read-HostWithCompletion `
            -Prompt "Application Name" `
            -Suggestions $existingApps `
            -Required
    }

    $sanitizedAppForLookup = $AppName -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
    $existingVersions = @(Get-ExistingVersions -BasePath $BasePath -Vendor $sanitizedVendorForLookup -AppName $sanitizedAppForLookup)

    if (-not $Version) {
        $Version = Read-HostWithCompletion `
            -Prompt "Version" `
            -Suggestions $existingVersions `
            -Default "1.0.0"
    }

    if (-not $Description) {
        Write-Host "Description (optional): " -NoNewline
        $Description = Read-Host
    }

    # Sanitize names for folder creation (remove punctuation, replace spaces with underscores)
    $sanitizedPublisher = $Publisher -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
    $sanitizedAppName = $AppName -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
    $sanitizedVersion = $Version -replace '[\\/:*?"<>|]', '_'

    # Create folder structure: /vendor/app/version/
    $packagePath = Join-Path $BasePath $sanitizedPublisher $sanitizedAppName $sanitizedVersion

    Write-Host "`n--- Creating Package Structure ---" -ForegroundColor Cyan
    Write-Host "Package path: $packagePath"
    Write-Action1Log "Creating package folder structure: $packagePath" -Level INFO

    # Create directories including architecture-specific installer folders
    $directories = @(
        $packagePath,
        (Join-Path $packagePath "installers"),
        (Join-Path $packagePath "installers" "x86"),
        (Join-Path $packagePath "installers" "x64"),
        (Join-Path $packagePath "installers" "arm64"),
        (Join-Path $packagePath "scripts"),
        (Join-Path $packagePath "documentation")
    )

    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            Write-Action1Log "Creating directory: $dir" -Level DEBUG
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
    Write-Host "  Created folder structure" -ForegroundColor Green

    # Prompt for installers
    Write-Host "`n--- Add Installers ---" -ForegroundColor Cyan

    $installers = @{
        x86 = $null
        x64 = $null
        arm64 = $null
    }
    $installerType = "exe"
    $installSwitches = ""
    $uninstallSwitches = ""

    $architectures = @('x64', 'x86', 'arm64')

    foreach ($arch in $architectures) {
        Write-Host "`n$arch installer" -ForegroundColor Yellow
        $installerPath = Read-HostWithFileCompletion `
            -Prompt "Path (Enter to skip)" `
            -Filter "*.exe,*.msi" `
            -BasePath $BasePath

        if ($installerPath -and (Test-Path $installerPath -PathType Leaf)) {
            $installerFile = Get-Item $installerPath
            $extension = $installerFile.Extension.ToLower()

            if ($extension -notin @('.exe', '.msi')) {
                Write-Host "  Skipped: Unsupported type ($extension)" -ForegroundColor Yellow
                continue
            }

            # Copy installer to architecture folder
            $destPath = Join-Path $packagePath "installers" $arch $installerFile.Name
            Copy-Item -Path $installerFile.FullName -Destination $destPath -Force
            Write-Host "  Added: $($installerFile.Name)" -ForegroundColor Green

            $installers[$arch] = @{
                FileName = $installerFile.Name
                Path = $destPath
                Size = $installerFile.Length
                Type = if ($extension -eq '.msi') { 'msi' } else { 'exe' }
            }

            # Use first installer's type as default
            if (-not $installerType -or $installerType -eq 'exe') {
                $installerType = $installers[$arch].Type
            }
        }
        elseif ($installerPath) {
            Write-Host "  File not found: $installerPath" -ForegroundColor Red
        }
    }

    # Check if at least one installer was added
    $hasInstallers = ($installers.Values | Where-Object { $_ -ne $null }).Count -gt 0

    if (-not $hasInstallers) {
        Write-Host "`nNo installers added. You can add them later to:" -ForegroundColor Yellow
        Write-Host "  $packagePath\installers\<arch>\" -ForegroundColor Cyan
    }
    else {
        # Prompt for install switches
        Write-Host "`n--- Silent Install Arguments ---" -ForegroundColor Cyan

        if ($installerType -eq 'msi') {
            Write-Host "Default MSI switches: $script:DefaultMsiSwitches (automatically added by Action1)"
            Write-Host "Additional install switches (press Enter for none): " -NoNewline
            $installSwitches = Read-Host
        }
        else {
            Write-Host "Common silent switches:"
            Write-Host "  /S              - NSIS"
            Write-Host "  /verysilent     - Inno Setup"
            Write-Host "  /quiet          - Many installers"
            Write-Host "Install switches [/S]: " -NoNewline
            $installSwitches = Read-Host
            if (-not $installSwitches) { $installSwitches = "/S" }
        }

        Write-Host "Uninstall switches [same as install]: " -NoNewline
        $uninstallSwitches = Read-Host
        if (-not $uninstallSwitches) { $uninstallSwitches = $installSwitches }
    }

    # Prompt for version/release information
    Write-Host "`n--- Version Information ---" -ForegroundColor Cyan

    # Release date
    $defaultReleaseDate = Get-Date -Format "yyyy-MM-dd"
    Write-Host "Release Date (yyyy-MM-dd) [$defaultReleaseDate]: " -NoNewline
    $releaseDate = Read-Host
    if (-not $releaseDate) { $releaseDate = $defaultReleaseDate }
    # Validate date format
    try {
        [datetime]::ParseExact($releaseDate, "yyyy-MM-dd", $null) | Out-Null
    }
    catch {
        Write-Host "  Invalid date format, using today's date" -ForegroundColor Yellow
        $releaseDate = $defaultReleaseDate
    }

    # Update Type
    $updateTypes = @('Regular Updates', 'Security Updates', 'Critical Updates')
    Write-Host "`nUpdate Type:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $updateTypes.Count; $i++) {
        $marker = if ($i -eq 0) { " (default)" } else { "" }
        Write-Host "  [$i] $($updateTypes[$i])$marker"
    }
    $updateTypeSelection = Read-Host "`nEnter selection (0-$($updateTypes.Count - 1))"
    if (-not $updateTypeSelection) { $updateTypeSelection = "0" }
    $updateType = $updateTypes[[int]$updateTypeSelection]
    Write-Host "Selected: $updateType" -ForegroundColor Green

    # Security Severity (only if Security Updates)
    $securitySeverity = "Unspecified"
    if ($updateType -eq 'Security Updates') {
        $severities = @('Unspecified', 'Low', 'Medium', 'High', 'Critical')
        Write-Host "`nSecurity Severity:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $severities.Count; $i++) {
            $marker = if ($i -eq 0) { " (default)" } else { "" }
            Write-Host "  [$i] $($severities[$i])$marker"
        }
        $severitySelection = Read-Host "`nEnter selection (0-$($severities.Count - 1))"
        if (-not $severitySelection) { $severitySelection = "0" }
        $securitySeverity = $severities[[int]$severitySelection]
        Write-Host "Selected: $securitySeverity" -ForegroundColor Green
    }

    # CVEs (optional)
    Write-Host "`nCVEs (comma-separated, optional): " -NoNewline
    $cvesInput = Read-Host
    $cves = @()
    if ($cvesInput) {
        $cves = $cvesInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    # EULA (optional)
    Write-Host "EULA URL or text (optional): " -NoNewline
    $eula = Read-Host

    # Additional Actions (optional)
    Write-Host "`nAdditional Actions (optional):" -ForegroundColor Cyan
    $actionOptions = @(
        @{ Name = 'Deploy Software'; Value = 'deploy_software' }
        @{ Name = 'Deploy Updates'; Value = 'deploy_updates' }
        @{ Name = 'Reboot'; Value = 'reboot' }
        @{ Name = 'Run Script'; Value = 'run_script' }
        @{ Name = 'Uninstall Software'; Value = 'uninstall_software' }
        @{ Name = 'Update Ring'; Value = 'update_ring' }
    )
    for ($i = 0; $i -lt $actionOptions.Count; $i++) {
        Write-Host "  [$i] $($actionOptions[$i].Name)"
    }
    $actionsInput = Read-Host "`nEnter selection(s) (0-$($actionOptions.Count - 1), comma-separated, Enter to skip)"

    $additionalActions = @()
    if ($actionsInput) {
        $selectedIndices = $actionsInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
        foreach ($idx in $selectedIndices) {
            $index = [int]$idx
            if ($index -ge 0 -and $index -lt $actionOptions.Count) {
                $action = @{
                    Type = $actionOptions[$index].Value
                    Name = $actionOptions[$index].Name
                }

                # For Run Script, we'll add script selection later
                if ($action.Type -eq 'run_script') {
                    Write-Host "  Script selection will be configured during deployment" -ForegroundColor DarkGray
                    $action.ScriptId = ""
                    $action.ScriptName = ""
                }

                $additionalActions += $action
            }
        }
        if ($additionalActions.Count -gt 0) {
            Write-Host "Selected: $($additionalActions.Name -join ', ')" -ForegroundColor Green
        }
    }

    # Build installers array for manifest
    $installersArray = @()
    foreach ($arch in $architectures) {
        if ($installers[$arch]) {
            $installersArray += @{
                Architecture = $arch
                FileName = $installers[$arch].FileName
                Type = $installers[$arch].Type
            }
        }
    }

    # Generate app name match patterns for Action1 detection
    $appNamePatterns = Get-AppNameMatchPatterns -AppName $AppName

    # Create manifest
    $manifest = [PSCustomObject]@{
        AppName = $AppName
        Publisher = $Publisher
        Description = if ($Description) { $Description } else { "" }
        Version = $Version
        ReleaseDate = $releaseDate
        CreatedDate = Get-Date -Format "yyyy-MM-dd"
        LastModified = Get-Date -Format "yyyy-MM-dd"
        InstallerType = $installerType
        Installers = $installersArray
        InstallSwitches = $installSwitches
        UninstallSwitches = $uninstallSwitches
        AppNameMatch = @{
            Specific = $appNamePatterns.Specific
            Broad = $appNamePatterns.Broad
        }
        UpdateInfo = @{
            UpdateType = $updateType
            SecuritySeverity = $securitySeverity
            CVEs = $cves
            Eula = $eula
        }
        AdditionalActions = $additionalActions
        DetectionMethod = @{
            Type = "registry"
            Path = ""
            Value = ""
        }
        Requirements = @{
            OSVersion = ""
            MinDiskSpaceMB = 0
            MinMemoryMB = 0
        }
        Action1Config = @{
            OrganizationId = ""
            PackageId = ""
            PolicyId = ""
            DeploymentGroup = ""
        }
        Metadata = @{
            Tags = @()
            Notes = ""
        }
    }

    # Save manifest
    $manifestPath = Join-Path $packagePath "manifest.json"
    Write-Action1Log "Creating manifest file: $manifestPath" -Level INFO
    Write-ManifestFile -Manifest $manifest -Path $manifestPath

    # Create README
    $installersList = if ($installersArray.Count -gt 0) {
        ($installersArray | ForEach-Object { "- **$($_.Architecture)**: $($_.FileName)" }) -join "`n"
    } else {
        "- No installers added yet"
    }

    $msiNote = if ($installerType -eq 'msi') { "**Note:** Action1 automatically adds: $script:DefaultMsiSwitches" } else { "" }
    $switchesDisplay = if ($installSwitches) { $installSwitches } else { '(default)' }

    $readmeContent = @(
        "# $AppName - Action1 Deployment Package",
        "",
        "## Overview",
        "$Description",
        "",
        "**Publisher:** $Publisher",
        "**Version:** $Version",
        "**Created:** $(Get-Date -Format 'yyyy-MM-dd')",
        "",
        "## Structure",
        "- **installers/** - Architecture-specific installer files",
        "  - **x86/** - 32-bit installers",
        "  - **x64/** - 64-bit installers",
        "  - **arm64/** - ARM64 installers",
        "- **scripts/** - Pre/post installation scripts",
        "- **documentation/** - Additional documentation",
        "- **manifest.json** - Application deployment configuration",
        "",
        "## Installers",
        "$installersList",
        "",
        "## Installation",
        "**Installer Type:** $installerType",
        "**Install Switches:** $switchesDisplay",
        "$msiNote",
        "",
        "## Usage",
        '```powershell',
        "# Deploy to Action1",
        "Deploy-Action1AppPackage -ManifestPath `"$manifestPath`"",
        "",
        "# Deploy update to existing application",
        "Deploy-Action1AppUpdate -ManifestPath `"$manifestPath`"",
        '```'
    ) -join "`n"

    $readmePath = Join-Path $packagePath "README.md"
    Set-Content -Path $readmePath -Value $readmeContent -Force
    Write-Action1Log "Created README file: $readmePath" -Level DEBUG

    # Display summary
    Write-Host "`n=== Package Summary ===" -ForegroundColor Green
    Write-Host "  Vendor:   $Publisher" -ForegroundColor White
    Write-Host "  App:      $AppName" -ForegroundColor White
    Write-Host "  Version:  $Version" -ForegroundColor White
    Write-Host "  Location: $packagePath" -ForegroundColor Cyan

    if ($installersArray.Count -gt 0) {
        Write-Host "`n  Installers:" -ForegroundColor White
        foreach ($inst in $installersArray) {
            Write-Host "    $($inst.Architecture): $($inst.FileName)" -ForegroundColor Gray
        }
    }

    Write-Host "`n✓ Package created successfully!" -ForegroundColor Green
    Write-Host "  Manifest: $manifestPath" -ForegroundColor Cyan

    Write-Action1Log "Package created successfully at: $packagePath" -Level INFO

    return [PSCustomObject]@{
        Success = $true
        PackagePath = $packagePath
        ManifestPath = $manifestPath
        AppName = $AppName
        Version = $Version
        Publisher = $Publisher
        InstallerType = $installerType
        Installers = $installersArray
        Manifest = $manifest
    }
}
