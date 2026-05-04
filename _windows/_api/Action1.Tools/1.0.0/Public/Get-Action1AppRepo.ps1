function Get-Action1AppRepo {
    <#
    .SYNOPSIS
        Gets information about a local application repository.

    .DESCRIPTION
        Scans a local application repository folder (vendor/app level) and returns
        information about all available package versions, including their manifests
        and installer files.

    .PARAMETER Path
        Path to the application repository folder (vendor/app level).
        This should be the folder containing version subfolders.

    .PARAMETER Vendor
        Vendor/Publisher name. Used with BasePath to construct the app repo path.

    .PARAMETER AppName
        Application name. Used with BasePath and Vendor to construct the app repo path.

    .PARAMETER BasePath
        Base path where vendor folders are located. Defaults to current directory.
        Used with Vendor and AppName parameters.

    .EXAMPLE
        Get-Action1AppRepo -Path ".\Microsoft\PowerShell"
        # Gets all versions of PowerShell from the specified path

    .EXAMPLE
        Get-Action1AppRepo -Vendor "Microsoft" -AppName "PowerShell"
        # Gets all versions using vendor/app name lookup from current directory

    .EXAMPLE
        Get-Action1AppRepo -BasePath "C:\Packages" -Vendor "7-Zip" -AppName "7-Zip"
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPath')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByPath', Position = 0)]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Vendor,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$AppName,

        [Parameter(ParameterSetName = 'ByName')]
        [string]$BasePath = (Get-Location).Path
    )

    try {
        # Determine the app repo path
        if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
            $appRepoPath = $Path
        }
        else {
            # Sanitize names for folder lookup (remove punctuation, replace spaces with underscores)
            $sanitizedVendor = $Vendor -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
            $sanitizedApp = $AppName -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
            $appRepoPath = Join-Path $BasePath $sanitizedVendor $sanitizedApp
        }

        if (-not (Test-Path $appRepoPath -PathType Container)) {
            throw "Application repository not found: $appRepoPath"
        }

        Write-Host "`n=== Application Repository Information ===" -ForegroundColor Cyan
        Write-Host "Path: $appRepoPath" -ForegroundColor Gray

        # Get all version folders
        $versionFolders = Get-ChildItem -Path $appRepoPath -Directory -ErrorAction SilentlyContinue

        if ($versionFolders.Count -eq 0) {
            Write-Host "No version folders found." -ForegroundColor Yellow
            return @{
                Path = $appRepoPath
                Versions = @()
            }
        }

        # Collect information about each version
        $versions = @()
        $appName = $null
        $publisher = $null

        foreach ($versionFolder in $versionFolders) {
            $manifestPath = Join-Path $versionFolder.FullName "manifest.json"

            if (Test-Path $manifestPath) {
                $manifest = Read-ManifestFile -Path $manifestPath

                # Get app info from first manifest
                if (-not $appName -and $manifest.AppName) {
                    $appName = $manifest.AppName
                    $publisher = $manifest.Publisher
                }

                # Count installers
                $installerCount = 0
                $architectures = @()

                if ($manifest.Installers -and $manifest.Installers.Count -gt 0) {
                    $installerCount = $manifest.Installers.Count
                    $architectures = $manifest.Installers | ForEach-Object { $_.Architecture }
                }

                $versions += [PSCustomObject]@{
                    Version = $manifest.Version
                    ReleaseDate = $manifest.ReleaseDate
                    InstallerType = $manifest.InstallerType
                    InstallerCount = $installerCount
                    Architectures = ($architectures -join ', ')
                    ManifestPath = $manifestPath
                    FolderPath = $versionFolder.FullName
                    Manifest = $manifest
                }
            }
            else {
                Write-Action1Log "No manifest found in: $($versionFolder.FullName)" -Level WARN
            }
        }

        # Sort versions (attempt semantic versioning sort)
        $versions = $versions | Sort-Object {
            try {
                [version]$_.Version
            }
            catch {
                $_.Version
            }
        } -Descending

        # Display summary
        Write-Host "`nApplication: $appName" -ForegroundColor Green
        Write-Host "Publisher: $publisher" -ForegroundColor Green
        Write-Host "Total Versions: $($versions.Count)" -ForegroundColor Green

        Write-Host "`n--- Available Versions ---" -ForegroundColor Cyan
        foreach ($ver in $versions) {
            $archInfo = if ($ver.Architectures) { " [$($ver.Architectures)]" } else { "" }
            Write-Host "  v$($ver.Version) - $($ver.ReleaseDate)$archInfo"
        }

        return [PSCustomObject]@{
            Path = $appRepoPath
            AppName = $appName
            Publisher = $publisher
            VersionCount = $versions.Count
            Versions = $versions
        }
    }
    catch {
        Write-Error "Failed to get application repository info: $($_.Exception.Message)"
    }
}
