function Get-Action1AppPackage {
    <#
    .SYNOPSIS
        Retrieves information about Action1 applications with interactive drill-down.

    .DESCRIPTION
        Lists applications or gets details about a specific application from Action1.
        If no OrganizationId is provided, prompts user to select from available organizations,
        then allows drilling down into repos, apps, and versions.

    .PARAMETER OrganizationId
        Action1 organization ID. If not specified, prompts user to select.

    .PARAMETER PackageId
        Specific package/repo ID to retrieve.

    .PARAMETER VersionId
        Specific version ID to retrieve (requires PackageId).

    .PARAMETER Name
        Filter by application name.

    .PARAMETER NoInteractive
        Disable interactive drill-down mode. By default, when no parameters are provided,
        interactive mode is enabled to browse repos → versions.

    .EXAMPLE
        Get-Action1AppPackage
        # Full interactive drill-down through org → repo → version

    .EXAMPLE
        Get-Action1AppPackage -NoInteractive
        # Returns repos list without drill-down prompts

    .EXAMPLE
        Get-Action1AppPackage -OrganizationId "org123" -Name "7-Zip"
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
        [string]$Name,

        [Parameter()]
        [switch]$NoInteractive
    )

    try {
        # If no OrganizationId provided, prompt for selection
        if (-not $OrganizationId) {
            $selectedOrg = Select-Action1Organization -IncludeAll $true
            if (-not $selectedOrg) {
                throw "No organization selected."
            }
            $OrganizationId = $selectedOrg.Id
        }

        # If specific version requested
        if ($PackageId -and $VersionId) {
            $version = Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId/$PackageId/versions/$VersionId" `
                -Method GET
            return ($version | Expand-NestedJsonAttributes -ExpandFileNames -FormatNested)
        }

        # If specific package requested (list versions)
        if ($PackageId) {
            # Fetch package with all fields to get embedded versions array
            $response = Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId/$PackageId`?fields=*" `
                -Method GET

            $versions = if ($response.versions) { @($response.versions) } else { @() }
            return ($versions | Expand-NestedJsonAttributes -ExpandFileNames -FormatNested)
        }

        # Get repos list
        $response = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId`?custom=yes&builtin=no&limit=100" `
            -Method GET

        $repos = if ($response.items) { @($response.items) } else { @($response) }

        if ($Name) {
            $repos = $repos | Where-Object { $_.name -like "*$Name*" }
        }

        # If NoInteractive flag set, just return the repos
        if ($NoInteractive) {
            return $repos
        }

        # Interactive mode - drill down through repos → versions
        if ($repos.Count -eq 0) {
            Write-Host "`nNo repositories found." -ForegroundColor Yellow
            return @()
        }

        # Select a repo
        Write-Host "`nSelect Repository:" -ForegroundColor Cyan
        Write-Host "  [0] Return all repositories (no drill-down)"
        for ($i = 0; $i -lt $repos.Count; $i++) {
            $repo = $repos[$i]
            $platform = if ($repo.platform) { " [$($repo.platform)]" } else { "" }
            Write-Host "  [$($i + 1)] $($repo.name)$platform - $($repo.vendor)"
        }

        $repoSelection = Read-Host "`nEnter selection (0-$($repos.Count))"
        $repoNum = [int]$repoSelection

        if ($repoNum -eq 0) {
            return $repos
        }

        if ($repoNum -lt 1 -or $repoNum -gt $repos.Count) {
            throw "Invalid selection."
        }

        $selectedRepo = $repos[$repoNum - 1]
        Write-Host "Selected: $($selectedRepo.name)" -ForegroundColor Green

        # Fetch package with all fields to get embedded versions array
        Write-Action1Log "Fetching versions for $($selectedRepo.name)..." -Level INFO
        $packageResponse = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId/$($selectedRepo.id)?fields=*" `
            -Method GET

        # Versions are embedded in the package response when using fields=*
        $versions = if ($packageResponse.versions) {
            @($packageResponse.versions)  # Force array in case of single item
        } else {
            @()
        }

        Write-Action1Log "Found $($versions.Count) version(s)" -Level DEBUG

        if ($versions.Count -eq 0) {
            Write-Host "`nNo versions found for this repository." -ForegroundColor Yellow
            return $selectedRepo
        }

        # Select a version
        Write-Host "`nSelect Version:" -ForegroundColor Cyan
        Write-Host "  [0] Return all versions (no drill-down)"
        for ($i = 0; $i -lt $versions.Count; $i++) {
            $ver = $versions[$i]
            $status = if ($ver.status) { " ($($ver.status))" } else { "" }
            $date = if ($ver.release_date) { " - $($ver.release_date)" } else { "" }
            Write-Host "  [$($i + 1)] v$($ver.version)$status$date"
        }

        $verSelection = Read-Host "`nEnter selection (0-$($versions.Count))"
        $verNum = [int]$verSelection

        if ($verNum -eq 0) {
            return ($versions | Expand-NestedJsonAttributes -ExpandFileNames -FormatNested)
        }

        if ($verNum -lt 1 -or $verNum -gt $versions.Count) {
            throw "Invalid selection."
        }

        $selectedVersion = $versions[$verNum - 1]
        Write-Host "Selected: v$($selectedVersion.version)" -ForegroundColor Green

        # Fetch full version details
        Write-Action1Log "Fetching version details..." -Level INFO
        $versionDetails = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId/$($selectedRepo.id)/versions/$($selectedVersion.id)" `
            -Method GET

        return ($versionDetails | Expand-NestedJsonAttributes -ExpandFileNames -FormatNested)
    }
    catch {
        Write-Error "Failed to retrieve applications: $($_.Exception.Message)"
    }
}
