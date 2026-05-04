function Deploy-Action1AppPackage {
    <#
    .SYNOPSIS
        Deploys an application to Action1 Software Repository.

    .DESCRIPTION
        Deploys an application using the correct Action1 Software Repository API flow:
        1. Prompts for organization (or uses manifest/parameter value)
        2. Finds matching repository or creates a new one
        3. Creates a new version entry
        4. Uploads installer file(s) using resumable upload protocol

    .PARAMETER ManifestPath
        Path to the manifest.json file.

    .PARAMETER OrganizationId
        Action1 organization ID. If not specified, uses value from manifest or prompts.

    .PARAMETER DryRun
        Shows what would be deployed without actually deploying.

    .EXAMPLE
        Deploy-Action1AppPackage -ManifestPath ".\PowerShell\manifest.json"

    .EXAMPLE
        Deploy-Action1AppPackage -ManifestPath ".\7-Zip\manifest.json" -OrganizationId "all"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [switch]$DryRun
    )

    Write-Host "`n=== Action1 Software Repository Deployment ===" -ForegroundColor Cyan

    # Load manifest
    $manifest = Read-ManifestFile -Path $ManifestPath
    $repoPath = Split-Path $ManifestPath -Parent

    # Handle multiple installers from manifest
    $installers = @()
    if ($manifest.Installers -and $manifest.Installers.Count -gt 0) {
        foreach ($inst in $manifest.Installers) {
            $archFolder = switch ($inst.Architecture) {
                'x64' { 'x64' }
                'x86' { 'x86' }
                'arm64' { 'arm64' }
                default { '' }
            }
            $installerPath = if ($archFolder) {
                Join-Path $repoPath "installers" $archFolder $inst.FileName
            } else {
                Join-Path $repoPath "installers" $inst.FileName
            }

            if (Test-Path $installerPath) {
                $platform = switch ($inst.Architecture) {
                    'x64' { 'Windows_64' }
                    'x86' { 'Windows_32' }
                    'arm64' { 'Windows_ARM64' }
                    default { 'Windows_64' }
                }
                $installers += @{
                    Path = $installerPath
                    FileName = $inst.FileName
                    Platform = $platform
                    Type = $inst.Type
                }
            } else {
                Write-Action1Log "Installer not found: $installerPath" -Level WARN
            }
        }
    }

    # Fallback to legacy InstallerFileName if no installers found
    if ($installers.Count -eq 0 -and $manifest.InstallerFileName) {
        $legacyPath = Join-Path $repoPath "installers" $manifest.InstallerFileName
        if (Test-Path $legacyPath) {
            $installers += @{
                Path = $legacyPath
                FileName = $manifest.InstallerFileName
                Platform = 'Windows_64'
                Type = $manifest.InstallerType
            }
        }
    }

    if ($installers.Count -eq 0) {
        throw "No installer files found in manifest or installers directory"
    }

    Write-Action1Log "Found $($installers.Count) installer(s) to upload" -Level INFO

    # Step 1: Get organization ID
    if (-not $OrganizationId) {
        if ($manifest.Action1Config.OrganizationId) {
            $OrganizationId = $manifest.Action1Config.OrganizationId
            Write-Host "Using organization from manifest: $OrganizationId" -ForegroundColor Green
        } else {
            $selectedOrg = Select-Action1Organization -IncludeAll $true
            $OrganizationId = $selectedOrg.Id

            # Save to manifest for future use
            $manifest.Action1Config.OrganizationId = $OrganizationId
            Write-ManifestFile -Manifest $manifest -Path $ManifestPath
        }
    }

    # Check for -WhatIf or -DryRun
    $isWhatIf = $WhatIfPreference -or $DryRun

    if ($isWhatIf) {
        Write-Host "`n=== Deployment Preview (WhatIf/DryRun) ===" -ForegroundColor Yellow
        Write-Host "Would deploy the following:"
        Write-Host "  App Name: $($manifest.AppName)"
        Write-Host "  Publisher: $($manifest.Publisher)"
        Write-Host "  Version: $($manifest.Version)"
        Write-Host "  Organization: $OrganizationId"
        Write-Host "  Installers:"
        foreach ($inst in $installers) {
            Write-Host "    - $($inst.FileName) ($($inst.Platform))"
        }
        return @{
            Success = $true
            DryRun = $true
            AppName = $manifest.AppName
            Version = $manifest.Version
        }
    }

    Write-Host "`nPreparing deployment..." -ForegroundColor Yellow

    try {
        # Step 2: Select or create software repository
        Write-Host "`nStep 1: Select software repository..." -ForegroundColor Cyan

        $repoSelection = Select-Action1SoftwareRepository `
            -OrganizationId $OrganizationId `
            -DefaultName $manifest.AppName `
            -DefaultVendor $manifest.Publisher `
            -DefaultPlatform 'Windows'

        $repositoryId = $repoSelection.Id
        $isNewRepo = $repoSelection.IsNew

        Write-Host "Repository ID: $repositoryId" -ForegroundColor Green

        # Step 3: Create version
        Write-Host "`nStep 2: Creating version $($manifest.Version)..." -ForegroundColor Cyan

        # Use first installer for the version creation
        $primaryInstaller = $installers[0]

        # Use AppNameMatch from manifest if available, otherwise generate from AppName
        $appNameMatch = if ($manifest.AppNameMatch -and $manifest.AppNameMatch.Specific) {
            $manifest.AppNameMatch.Specific
        } elseif ($manifest.AppNameMatch -and $manifest.AppNameMatch.Broad) {
            Write-Action1Log "No Specific app name match pattern found, using Broad pattern" -Level WARN
            $manifest.AppNameMatch.Broad
        } else {
            $patterns = Get-AppNameMatchPatterns -AppName $manifest.AppName
            $patterns.Specific
        }

        # Get update info from manifest if available
        $releaseDate = if ($manifest.ReleaseDate) { $manifest.ReleaseDate } else { Get-Date -Format 'yyyy-MM-dd' }
        $updateType = if ($manifest.UpdateInfo -and $manifest.UpdateInfo.UpdateType) { $manifest.UpdateInfo.UpdateType } else { 'Regular Updates' }
        $securitySeverity = if ($manifest.UpdateInfo -and $manifest.UpdateInfo.SecuritySeverity) { $manifest.UpdateInfo.SecuritySeverity } else { 'Unspecified' }
        $securityCVE = if ($manifest.UpdateInfo -and $manifest.UpdateInfo.CVEs) {
            ($manifest.UpdateInfo.CVEs) -join ', '
        } else { "" }

        # Build hashtable of all platform files
        $allPlatformFiles = @{}
        foreach ($inst in $installers) {
            $allPlatformFiles[$inst.Platform] = $inst.FileName
        }

        $versionResponse = New-Action1RepositoryVersion `
            -OrganizationId $OrganizationId `
            -RepositoryId $repositoryId `
            -Version $manifest.Version `
            -AppNameMatch $appNameMatch `
            -FileName $primaryInstaller.FileName `
            -Platform $primaryInstaller.Platform `
            -InstallType $manifest.InstallerType `
            -ReleaseDate $releaseDate `
            -UpdateType $updateType `
            -SecuritySeverity $securitySeverity `
            -SecurityCVE $securityCVE `
            -AllPlatformFiles $allPlatformFiles

        $versionId = $versionResponse.id
        Write-Host "Version created with ID: $versionId" -ForegroundColor Green

        # Step 4: Upload installer file(s)
        Write-Host "`nStep 3: Uploading installer file(s)..." -ForegroundColor Cyan

        if ($installers.Count -gt 1) {
            # Use parallel uploads for multiple architectures
            $uploads = $installers | ForEach-Object {
                @{
                    FilePath = $_.Path
                    Platform = $_.Platform
                }
            }

            $uploadResults = Invoke-Action1MultiFileUpload `
                -Uploads $uploads `
                -OrganizationId $OrganizationId `
                -PackageId $repositoryId `
                -VersionId $versionId `
                -ChunkSizeMB 24

            $failedUploads = $uploadResults | Where-Object { -not $_.Success }
            if ($failedUploads) {
                throw "One or more uploads failed: $(($failedUploads | ForEach-Object { "$($_.Platform): $($_.Error)" }) -join '; ')"
            }
        }
        else {
            # Single file upload
            foreach ($installer in $installers) {
                $null = Invoke-Action1SoftwareRepoUpload `
                    -FilePath $installer.Path `
                    -OrganizationId $OrganizationId `
                    -PackageId $repositoryId `
                    -VersionId $versionId `
                    -Platform $installer.Platform `
                    -ChunkSizeMB 24

                Write-Host "✓ Upload complete: $($installer.FileName)" -ForegroundColor Green
            }
        }

        # Update manifest with IDs
        $manifest.Action1Config.PackageId = $repositoryId
        Write-ManifestFile -Manifest $manifest -Path $ManifestPath

        Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
        Write-Host "Application: $($manifest.AppName) v$($manifest.Version)"
        Write-Host "Organization: $OrganizationId"
        Write-Host "Repository ID: $repositoryId"
        Write-Host "Version ID: $versionId"
        Write-Host "Status: Ready for deployment"

        return @{
            Success = $true
            OrganizationId = $OrganizationId
            RepositoryId = $repositoryId
            VersionId = $versionId
            AppName = $manifest.AppName
            Version = $manifest.Version
        }
    }
    catch {
        Write-Error "Deployment failed: $($_.Exception.Message)"
        Write-Action1Log "Deployment failed" -Level ERROR -ErrorRecord $_
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}
