function Export-Action1AppPackage {
    <#
    .SYNOPSIS
        Exports an Action1 app package/version to local file structure.

    .DESCRIPTION
        The opposite of Deploy-Action1AppPackage. Fetches an app package version from
        Action1 Software Repository and exports it to the local manifest.json format,
        including downloading the installer files and capturing Additional Actions configuration.

    .PARAMETER OrganizationId
        Action1 organization ID. If not specified, prompts for selection.

    .PARAMETER PackageId
        The software repository package ID. If not specified, prompts for selection.

    .PARAMETER VersionId
        The specific version ID to export. If not specified, prompts for selection.

    .PARAMETER OutputPath
        The base output path where the package will be exported.
        Creates: OutputPath/Vendor/AppName/Version/
        Defaults to current directory.

    .PARAMETER SkipInstallerDownload
        If specified, skips downloading installer files (only exports manifest).

    .PARAMETER Force
        If specified, overwrites existing files without prompting.

    .PARAMETER PageSize
        Number of items to display per page when browsing built-in packages.
        Defaults to 10.

    .EXAMPLE
        Export-Action1AppPackage
        # Full interactive - prompts for org, package, version, and output path

    .EXAMPLE
        Export-Action1AppPackage -OrganizationId "org123" -PackageId "pkg456" -VersionId "ver789"
        # Exports specific version to current directory

    .EXAMPLE
        Export-Action1AppPackage -OutputPath "C:\Packages" -SkipInstallerDownload
        # Exports manifest only without downloading installers
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$PackageId,

        [Parameter()]
        [string]$VersionId,

        [Parameter()]
        [string]$OutputPath = (Get-Location).Path,

        # FIXME: Unable to find way to get a download uri via API. This must be pushed to the agent during deployment.
        [Parameter()]
        [switch]$SkipInstallerDownload,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [int]$PageSize = 10
    )

    Write-Host "`n=== Export Action1 App Package ===" -ForegroundColor Cyan

    try {
        # Step 1: Select organization if not provided
        if (-not $OrganizationId) {
            $selectedOrg = Select-Action1Organization -IncludeAll $true
            if (-not $selectedOrg) {
                throw "No organization selected."
            }
            $OrganizationId = $selectedOrg.Id
        }

        # Step 2: Select package if not provided
        if (-not $PackageId) {
            # Ask user to choose between custom and built-in packages
            Write-Host "`nSelect Package Type:" -ForegroundColor Cyan
            Write-Host "  [1] Custom (your uploaded packages)"
            Write-Host "  [2] Built-in (Action1 library)"

            $typeSelection = Read-Host "`nEnter selection (1-2)"

            $isBuiltIn = $typeSelection -eq '2'

            Write-Host "`nFetching software repositories..." -ForegroundColor Yellow

            if ($isBuiltIn) {
                # Fetch all built-in packages once (API doesn't support offset pagination)
                $response = Invoke-Action1ApiRequest `
                    -Endpoint "software-repository/$OrganizationId`?custom=no&builtin=yes&limit=1000" `
                    -Method GET

                $allRepos = if ($response.items) { @($response.items) } else { @($response) }

                if ($allRepos.Count -eq 0) {
                    throw "No built-in software repositories found."
                }

                # Local pagination through fetched results
                $totalCount = $allRepos.Count
                $totalPages = [Math]::Ceiling($totalCount / $PageSize)
                $currentPage = 0
                $selectedRepo = $null

                while ($null -eq $selectedRepo) {
                    Clear-Host
                    $startIndex = $currentPage * $PageSize
                    $endIndex = [Math]::Min($startIndex + $PageSize, $totalCount)
                    $pageRepos = $allRepos[$startIndex..($endIndex - 1)]

                    Write-Host "Built-in Repositories (Page $($currentPage + 1) of $totalPages, Total: $totalCount):" -ForegroundColor Cyan
                    for ($i = 0; $i -lt $pageRepos.Count; $i++) {
                        $repo = $pageRepos[$i]
                        $platform = if ($repo.platform) { " [$($repo.platform)]" } else { "" }
                        Write-Host "  [$($i + 1)] $($repo.name)$platform - $($repo.vendor)"
                    }

                    # Navigation options
                    Write-Host ""
                    if ($currentPage -gt 0) {
                        Write-Host "  [P] Previous page" -ForegroundColor DarkGray
                    }
                    if ($currentPage -lt $totalPages - 1) {
                        Write-Host "  [N] Next page" -ForegroundColor DarkGray
                    }
                    Write-Host "  [Q] Cancel" -ForegroundColor DarkGray

                    $repoSelection = Read-Host "`nEnter selection (1-$($pageRepos.Count), P/N to navigate, Q to cancel)"

                    if ($repoSelection -eq 'Q' -or $repoSelection -eq 'q') {
                        throw "Selection cancelled."
                    }
                    elseif ($repoSelection -eq 'P' -or $repoSelection -eq 'p') {
                        if ($currentPage -gt 0) {
                            $currentPage--
                        }
                        else {
                            Write-Host "Already on first page." -ForegroundColor Yellow
                        }
                    }
                    elseif ($repoSelection -eq 'N' -or $repoSelection -eq 'n') {
                        if ($currentPage -lt $totalPages - 1) {
                            $currentPage++
                        }
                        else {
                            Write-Host "No more pages." -ForegroundColor Yellow
                        }
                    }
                    elseif ($repoSelection -match '^\d+$') {
                        $repoNum = [int]$repoSelection
                        if ($repoNum -ge 1 -and $repoNum -le $pageRepos.Count) {
                            $selectedRepo = $pageRepos[$repoNum - 1]
                        }
                        else {
                            Write-Host "Invalid selection. Please try again." -ForegroundColor Yellow
                        }
                    }
                    else {
                        Write-Host "Invalid input. Please try again." -ForegroundColor Yellow
                    }
                }

                $PackageId = $selectedRepo.id
                Write-Host "Selected: $($selectedRepo.name)" -ForegroundColor Green
            }
            else {
                # Custom packages - show all (no pagination needed, typically fewer)
                $response = Invoke-Action1ApiRequest `
                    -Endpoint "software-repository/$OrganizationId`?custom=yes&builtin=no&limit=100" `
                    -Method GET

                $repos = if ($response.items) { @($response.items) } else { @($response) }

                if ($repos.Count -eq 0) {
                    throw "No custom software repositories found."
                }

                Write-Host "`nCustom Repositories:" -ForegroundColor Cyan
                for ($i = 0; $i -lt $repos.Count; $i++) {
                    $repo = $repos[$i]
                    $platform = if ($repo.platform) { " [$($repo.platform)]" } else { "" }
                    Write-Host "  [$($i + 1)] $($repo.name)$platform - $($repo.vendor)"
                }

                $repoSelection = Read-Host "`nEnter selection (1-$($repos.Count))"
                $repoNum = [int]$repoSelection

                if ($repoNum -lt 1 -or $repoNum -gt $repos.Count) {
                    throw "Invalid selection."
                }

                $selectedRepo = $repos[$repoNum - 1]
                $PackageId = $selectedRepo.id
                Write-Host "Selected: $($selectedRepo.name)" -ForegroundColor Green
            }
        }
        else {
            # Fetch repo info
            $selectedRepo = Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId/$PackageId" `
                -Method GET
        }

        # Step 3: Get package details with versions
        Write-Host "`nFetching package versions..." -ForegroundColor Yellow
        $packageResponse = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId/$PackageId`?fields=*" `
            -Method GET

        $versions = if ($packageResponse.versions) { @($packageResponse.versions) } else { @() }

        if ($versions.Count -eq 0) {
            throw "No versions found for this repository."
        }

        # Step 4: Select version if not provided
        if (-not $VersionId) {
            Write-Host "`nSelect Version:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $versions.Count; $i++) {
                $ver = $versions[$i]
                $status = if ($ver.status) { " ($($ver.status))" } else { "" }
                $date = if ($ver.release_date) { " - $($ver.release_date)" } else { "" }
                Write-Host "  [$($i + 1)] v$($ver.version)$status$date"
            }

            $verSelection = Read-Host "`nEnter selection (1-$($versions.Count))"
            $verNum = [int]$verSelection

            if ($verNum -lt 1 -or $verNum -gt $versions.Count) {
                throw "Invalid selection."
            }

            $selectedVersion = $versions[$verNum - 1]
            $VersionId = $selectedVersion.id
        }
        else {
            $selectedVersion = $versions | Where-Object { $_.id -eq $VersionId } | Select-Object -First 1
            if (-not $selectedVersion) {
                throw "Version not found: $VersionId"
            }
        }

        Write-Host "Selected version: v$($selectedVersion.version)" -ForegroundColor Green

        # Step 5: Fetch full version details
        Write-Host "`nFetching version details..." -ForegroundColor Yellow
        $versionDetails = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId/$PackageId/versions/$VersionId" `
            -Method GET

        # Step 6: Build output folder structure
        $vendor = $packageResponse.vendor ?? $selectedRepo.vendor ?? "Unknown"
        $appName = $packageResponse.name ?? $selectedRepo.name ?? "Unknown"
        $version = $selectedVersion.version

        # Sanitize for folder names (remove punctuation, replace spaces with underscores)
        $sanitizedVendor = $vendor -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
        $sanitizedAppName = $appName -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
        $sanitizedVersion = $version -replace '[\\/:*?"<>|]', '_'

        $packagePath = Join-Path $OutputPath $sanitizedVendor $sanitizedAppName $sanitizedVersion
        $installersPath = Join-Path $packagePath "installers"

        # Check if folder exists
        if ((Test-Path $packagePath) -and -not $Force) {
            $overwrite = Read-Host "Output folder already exists: $packagePath`nOverwrite? (y/N)"
            if ($overwrite -ne 'y' -and $overwrite -ne 'Y') {
                Write-Host "Export cancelled." -ForegroundColor Yellow
                return
            }
        }

        # Create directories
        Write-Host "`nCreating folder structure..." -ForegroundColor Yellow
        New-Item -Path $packagePath -ItemType Directory -Force | Out-Null
        New-Item -Path $installersPath -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $packagePath "scripts") -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $packagePath "documentation") -ItemType Directory -Force | Out-Null

        # Step 7: Build installers array from file_name data
        $installers = @()
        $fileNameData = $versionDetails.file_name
        if ($fileNameData -is [PSCustomObject]) {
            foreach ($platformProp in $fileNameData.PSObject.Properties) {
                $platform = $platformProp.Name
                $fileInfo = $platformProp.Value

                # Map platform to architecture
                $architecture = switch ($platform) {
                    'Windows_64' { 'x64' }
                    'Windows_32' { 'x86' }
                    'Windows_ARM64' { 'arm64' }
                    'Mac_AppleSilicon' { 'arm64' }
                    'Mac_IntelCPU' { 'x64' }
                    default { $platform }
                }

                $fileName = if ($fileInfo -is [PSCustomObject]) { $fileInfo.name } else { $fileInfo }

                $installers += @{
                    FileName = $fileName
                    Architecture = $architecture
                    Platform = $platform
                }
            }
        }

        # Step 8: Build Additional Actions from API response
        $additionalActions = @()
        if ($versionDetails.additional_actions) {
            foreach ($action in $versionDetails.additional_actions) {
                # Extract display name from params.display_summary (for readability, not used on import)
                $displayName = ""
                if ($action.params -and $action.params.display_summary) {
                    $displayName = $action.params.display_summary
                }

                $actionObj = [ordered]@{
                    _DisplayName = $displayName
                    Name = $action.name
                    TemplateId = $action.template_id ?? $action.name
                    When = $action.when ?? ""
                    Priority = $action.priority ?? "1"
                    Id = $action.id ?? ""
                }

                # Extract all parameters
                if ($action.params) {
                    $actionObj.Params = @{}
                    foreach ($prop in $action.params.PSObject.Properties) {
                        $actionObj.Params[$prop.Name] = $prop.Value
                    }
                }

                $additionalActions += $actionObj
            }
        }

        # Step 9: Build manifest object
        $manifest = [PSCustomObject]@{
            AppName = $appName
            Publisher = $vendor
            Description = $packageResponse.description ?? ""
            Version = $version
            CreatedDate = Get-Date -Format "yyyy-MM-dd"
            LastModified = Get-Date -Format "yyyy-MM-dd"
            ReleaseDate = $selectedVersion.release_date ?? (Get-Date -Format "yyyy-MM-dd")
            InstallerType = $versionDetails.install_type ?? "msi"
            InstallerFileName = if ($installers.Count -gt 0) { $installers[0].FileName } else { "" }
            InstallSwitches = $versionDetails.install_parameters ?? ""
            UninstallSwitches = $versionDetails.uninstall_parameters ?? ""
            Installers = @(
                $installers | ForEach-Object {
                    [PSCustomObject]@{
                        FileName = $_.FileName
                        Architecture = $_.Architecture
                    }
                }
            )
            AppNameMatch = @{
                Specific = $versionDetails.app_name_match ?? ""
            }
            UpdateInfo = @{
                UpdateType = $versionDetails.update_type ?? "Regular Updates"
                SecuritySeverity = $versionDetails.security_severity ?? "Unspecified"
                CVEs = if ($versionDetails.cves) { @($versionDetails.cves) } else { @() }
                Eula = $versionDetails.eula ?? ""
            }
            AdditionalActions = $additionalActions
            DetectionMethod = @{
                Type = "registry"
                Path = ""
                Value = ""
            }
            Requirements = @{
                OSVersion = if ($versionDetails.os) { $versionDetails.os -join ", " } else { "" }
                Architecture = if ($installers.Count -gt 0) { $installers[0].Architecture } else { "x64" }
                MinDiskSpaceMB = 0
                MinMemoryMB = 0
            }
            ExitCodes = @{
                Success = $versionDetails.success_exit_codes ?? "0"
                Reboot = $versionDetails.reboot_exit_codes ?? "1641,3010"
            }
            Action1Config = @{
                OrganizationId = $OrganizationId
                PackageId = $PackageId
                VersionId = $VersionId
                Status = $versionDetails.status ?? "Published"
                ApprovalStatus = $versionDetails.approval_status ?? "Approved"
                EulaAccepted = $versionDetails.EULA_accepted ?? "no"
            }
            Metadata = @{
                Tags = @()
                Notes = $versionDetails.notes ?? ""
                ExportedFrom = "Action1"
                ExportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }

        # Step 10: Save manifest
        $manifestPath = Join-Path $packagePath "manifest.json"
        Write-ManifestFile -Manifest $manifest -Path $manifestPath
        Write-Host "  Manifest saved: $manifestPath" -ForegroundColor Green

        # Step 11: Extract scripts from Additional Actions
        $extractedScripts = @()
        if ($additionalActions.Count -gt 0) {
            $scriptsPath = Join-Path $packagePath "scripts"
            $hasScripts = $false

            foreach ($action in $additionalActions) {
                # Check if this is a run_script action with script content
                if ($action.TemplateId -eq "run_script" -and $action.Params -and $action.Params.run_script_text) {
                    $scriptText = $action.Params.run_script_text

                    # Skip empty scripts
                    if ([string]::IsNullOrWhiteSpace($scriptText)) {
                        continue
                    }

                    # Map "When" to install/uninstall
                    $whenPrefix = switch -Regex ($action.When) {
                        "install" { "install" }
                        "uninstall" { "uninstall" }
                        default { "other" }
                    }

                    # Get priority (default to 1)
                    $priority = if ($action.Priority) { $action.Priority } else { "1" }

                    # Sanitize name for filename
                    $scriptName = $action.Name -replace '[\\/:*?"<>|]', '_' -replace '\s+', '_'
                    $scriptName = $scriptName -replace '_+', '_' -replace '^_|_$', ''

                    # Determine script extension based on language (Bash = .sh, PowerShell = .ps1)
                    $scriptExt = if ($action.Params.run_script_language -eq "Bash") { ".sh" } else { ".ps1" }

                    # Build filename: <install/uninstall>_<priority>_<name>.<ext>
                    $scriptFileName = "${whenPrefix}_${priority}_${scriptName}${scriptExt}"
                    $scriptFilePath = Join-Path $scriptsPath $scriptFileName

                    # Create scripts folder if needed
                    if (-not $hasScripts) {
                        if (-not (Test-Path $scriptsPath)) {
                            $null = New-Item -ItemType Directory -Path $scriptsPath -Force
                        }
                        $hasScripts = $true
                    }

                    # Save script file
                    $scriptText | Out-File -FilePath $scriptFilePath -Encoding UTF8 -Force
                    $extractedScripts += $scriptFileName
                    Write-Host "  Script extracted: $scriptFileName" -ForegroundColor Cyan
                }
            }

            if ($extractedScripts.Count -gt 0) {
                Write-Host "  Scripts folder: $scriptsPath" -ForegroundColor Green
            }
        }

        # Step 12: Installer file information
        # Note: Action1 API does not support direct installer downloads.
        # Installers are downloaded by agents via a separate messaging protocol.
        if ($installers.Count -gt 0) {
            Write-Host "`nInstaller Files (referenced in manifest):" -ForegroundColor Yellow

            $binaryIds = $versionDetails.binary_id
            foreach ($installer in $installers) {
                $platform = $installer.Platform
                $binaryId = if ($binaryIds -is [PSCustomObject]) { $binaryIds.$platform } else { $null }

                Write-Host "  - $($installer.FileName) [$($installer.Architecture)]" -ForegroundColor Cyan
                if ($binaryId) {
                    Write-Host "    Agent cache: C:\Windows\Action1\package_downloads\CLOUD_$($binaryId)_files\" -ForegroundColor DarkGray
                }
            }
        }

        # Summary
        Write-Host "`n=== Export Complete ===" -ForegroundColor Green
        Write-Host "Application: $appName v$version" -ForegroundColor White
        Write-Host "Publisher: $vendor" -ForegroundColor White
        Write-Host "Location: $packagePath" -ForegroundColor Cyan
        Write-Host "Manifest: $manifestPath" -ForegroundColor Cyan
        Write-Host "Installers: $($installers.Count) referenced" -ForegroundColor White
        if ($additionalActions.Count -gt 0) {
            Write-Host "Additional Actions: $($additionalActions.Count) configured" -ForegroundColor White
        }
        if ($extractedScripts.Count -gt 0) {
            Write-Host "Scripts extracted: $($extractedScripts.Count)" -ForegroundColor Green
        }

        return @{
            Success = $true
            OutputPath = $packagePath
            ManifestPath = $manifestPath
            AppName = $appName
            Version = $version
            Publisher = $vendor
            InstallerCount = $installers.Count
            AdditionalActionsCount = $additionalActions.Count
            ExtractedScriptsCount = $extractedScripts.Count
            ExtractedScripts = $extractedScripts
        }
    }
    catch {
        Write-Error "Export failed: $($_.Exception.Message)"
        Write-Action1Log "Export failed" -Level ERROR -ErrorRecord $_
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}
