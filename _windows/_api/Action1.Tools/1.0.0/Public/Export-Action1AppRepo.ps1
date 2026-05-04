function Export-Action1AppRepo {
    <#
    .SYNOPSIS
        Exports an entire Action1 app repository to local file structure.

    .DESCRIPTION
        The opposite of Deploy-Action1AppRepo. Fetches an entire app repository from
        Action1 Software Repository including all versions, and exports them to the
        local manifest.json format with installer files and Additional Actions.

    .PARAMETER OrganizationId
        Action1 organization ID. If not specified, prompts for selection.

    .PARAMETER PackageId
        The software repository package ID. If not specified, prompts for selection.

    .PARAMETER OutputPath
        The base output path where the package will be exported.
        Creates: OutputPath/Vendor/AppName/Version/ for each version.
        Defaults to current directory.

    .PARAMETER VersionFilter
        Optional filter to export only specific versions. Supports wildcards.
        Example: "1.*" to export only 1.x versions.

    .PARAMETER SkipInstallerDownload
        If specified, skips downloading installer files (only exports manifests).

    .PARAMETER Force
        If specified, overwrites existing files without prompting.

    .PARAMETER PageSize
        Number of items to display per page when browsing built-in packages.
        Defaults to 10.

    .EXAMPLE
        Export-Action1AppRepo
        # Full interactive - prompts for org, package, and output path

    .EXAMPLE
        Export-Action1AppRepo -OrganizationId "org123" -PackageId "pkg456" -OutputPath "C:\Packages"
        # Exports all versions of specified package

    .EXAMPLE
        Export-Action1AppRepo -VersionFilter "23.*" -SkipInstallerDownload
        # Exports only version 23.x manifests without downloading installers
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$PackageId,

        [Parameter()]
        [string]$OutputPath = (Get-Location).Path,

        [Parameter()]
        [string]$VersionFilter,

        [Parameter()]
        [switch]$SkipInstallerDownload,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [int]$PageSize = 10
    )

    Write-Host "`n=== Export Action1 App Repository ===" -ForegroundColor Cyan

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

        # Step 3: Get package details with all versions
        Write-Host "`nFetching package versions..." -ForegroundColor Yellow
        $packageResponse = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId/$PackageId`?fields=*" `
            -Method GET

        $versions = if ($packageResponse.versions) { @($packageResponse.versions) } else { @() }

        if ($versions.Count -eq 0) {
            throw "No versions found for this repository."
        }

        # Apply version filter if specified
        if ($VersionFilter) {
            $versions = $versions | Where-Object { $_.version -like $VersionFilter }
            Write-Host "Filtered to $($versions.Count) version(s) matching '$VersionFilter'" -ForegroundColor Yellow
        }

        if ($versions.Count -eq 0) {
            throw "No versions match the specified filter."
        }

        $vendor = $packageResponse.vendor ?? $selectedRepo.vendor ?? "Unknown"
        $appName = $packageResponse.name ?? $selectedRepo.name ?? "Unknown"

        Write-Host "`nExporting $($versions.Count) version(s) of $appName by $vendor" -ForegroundColor Cyan

        # Export each version
        $results = @()
        $successCount = 0
        $failCount = 0

        foreach ($ver in $versions) {
            Write-Host "`n--- Exporting v$($ver.version) ---" -ForegroundColor Yellow

            try {
                $exportResult = Export-Action1AppPackage `
                    -OrganizationId $OrganizationId `
                    -PackageId $PackageId `
                    -VersionId $ver.id `
                    -OutputPath $OutputPath `
                    -SkipInstallerDownload:$SkipInstallerDownload `
                    -Force:$Force

                if ($exportResult.Success) {
                    $successCount++
                    $results += @{
                        Version = $ver.version
                        Success = $true
                        OutputPath = $exportResult.OutputPath
                    }
                }
                else {
                    $failCount++
                    $results += @{
                        Version = $ver.version
                        Success = $false
                        Error = $exportResult.Error
                    }
                }
            }
            catch {
                $failCount++
                $results += @{
                    Version = $ver.version
                    Success = $false
                    Error = $_.Exception.Message
                }
                Write-Error "Failed to export v$($ver.version): $($_.Exception.Message)"
            }
        }

        # Summary
        Write-Host "`n=== Export Summary ===" -ForegroundColor Cyan
        Write-Host "Application: $appName" -ForegroundColor Green
        Write-Host "Publisher: $vendor" -ForegroundColor Green
        Write-Host "Total Versions: $($versions.Count)"
        Write-Host "Successful: $successCount" -ForegroundColor Green
        if ($failCount -gt 0) {
            Write-Host "Failed: $failCount" -ForegroundColor Red
        }

        return @{
            Success = ($failCount -eq 0)
            AppName = $appName
            Publisher = $vendor
            OrganizationId = $OrganizationId
            PackageId = $PackageId
            TotalVersions = $versions.Count
            SuccessCount = $successCount
            FailCount = $failCount
            Results = $results
        }
    }
    catch {
        Write-Error "Repository export failed: $($_.Exception.Message)"
        Write-Action1Log "Repository export failed" -Level ERROR -ErrorRecord $_
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}
