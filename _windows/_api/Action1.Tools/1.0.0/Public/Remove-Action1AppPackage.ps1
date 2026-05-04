function Remove-Action1AppPackage {
    <#
    .SYNOPSIS
        Removes a package version from an Action1 software repository.

    .DESCRIPTION
        Interactively selects and deletes a specific package version from a software
        repository in Action1. Uses the same drill-down selector pattern as Get-Action1AppPackage.

    .PARAMETER OrganizationId
        Action1 organization ID. If not provided, prompts for selection.

    .PARAMETER PackageId
        Package ID. If not provided, prompts for selection.

    .PARAMETER VersionId
        Version ID to remove. If not provided, prompts for selection.

    .PARAMETER Force
        Skips confirmation prompt.

    .EXAMPLE
        Remove-Action1AppPackage
        # Interactive mode - prompts for org, repo, and version selection

    .EXAMPLE
        Remove-Action1AppPackage -OrganizationId "all" -PackageId "pkg123" -VersionId "ver456" -Force
        # Direct removal without prompts
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$PackageId,

        [Parameter()]
        [string]$VersionId,

        [Parameter()]
        [switch]$Force
    )

    try {
        # Step 1: Select organization
        if (-not $OrganizationId) {
            $selectedOrg = Select-Action1Organization -IncludeAll $true
            if (-not $selectedOrg) {
                Write-Host "Operation cancelled." -ForegroundColor Yellow
                return
            }
            $OrganizationId = $selectedOrg.Id
        }

        # Step 2: Select repository if not provided
        if (-not $PackageId) {
            Write-Host "`nFetching repositories..." -ForegroundColor Gray
            $response = Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId`?custom=yes&builtin=no&limit=100" `
                -Method GET

            $repos = if ($response.items) { @($response.items) } else { @($response) }

            if ($repos.Count -eq 0) {
                Write-Host "`nNo repositories found." -ForegroundColor Yellow
                return
            }

            Write-Host "`nSelect Repository:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $repos.Count; $i++) {
                $repo = $repos[$i]
                $platform = if ($repo.platform) { " [$($repo.platform)]" } else { "" }
                Write-Host "  [$i] $($repo.name)$platform - $($repo.vendor)"
            }

            $repoSelection = Read-Host "`nEnter selection (0-$($repos.Count - 1))"
            $repoNum = [int]$repoSelection

            if ($repoNum -lt 0 -or $repoNum -ge $repos.Count) {
                Write-Host "Invalid selection." -ForegroundColor Red
                return
            }

            $selectedRepo = $repos[$repoNum]
            Write-Host "Selected: $($selectedRepo.name)" -ForegroundColor Green
            $PackageId = $selectedRepo.id
        }

        # Step 3: Select version if not provided
        if (-not $VersionId) {
            Write-Host "`nFetching versions..." -ForegroundColor Gray
            $packageResponse = Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId/$PackageId`?fields=*" `
                -Method GET

            $versions = if ($packageResponse.versions) { @($packageResponse.versions) } else { @() }

            if ($versions.Count -eq 0) {
                Write-Host "`nNo versions found for this repository." -ForegroundColor Yellow
                return
            }

            Write-Host "`nSelect Version to Remove:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $versions.Count; $i++) {
                $ver = $versions[$i]
                $status = if ($ver.status) { " ($($ver.status))" } else { "" }
                $date = if ($ver.release_date) { " - $($ver.release_date)" } else { "" }
                Write-Host "  [$i] v$($ver.version)$status$date"
            }

            $verSelection = Read-Host "`nEnter selection (0-$($versions.Count - 1))"
            $verNum = [int]$verSelection

            if ($verNum -lt 0 -or $verNum -ge $versions.Count) {
                Write-Host "Invalid selection." -ForegroundColor Red
                return
            }

            $selectedVersion = $versions[$verNum]
            Write-Host "Selected: v$($selectedVersion.version)" -ForegroundColor Green
            $VersionId = $selectedVersion.id
        }

        # Get version info for confirmation
        $versionInfo = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId/$PackageId/versions/$VersionId" `
            -Method GET

        $confirmMsg = "version $($versionInfo.version) from package $PackageId"

        if ($Force -or $PSCmdlet.ShouldProcess($confirmMsg, "Remove")) {
            if (-not $Force) {
                Write-Host "`n⚠ WARNING: This will permanently delete version '$($versionInfo.version)'!" -ForegroundColor Red
                $confirm = Read-Host "Type 'DELETE' to confirm"
                if ($confirm -ne 'DELETE') {
                    Write-Host "Operation cancelled." -ForegroundColor Yellow
                    return
                }
            }

            Write-Host "`nDeleting version..." -ForegroundColor Yellow
            Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId/$PackageId/versions/$VersionId" `
                -Method DELETE

            Write-Host "✓ Version '$($versionInfo.version)' removed successfully" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to remove package version: $($_.Exception.Message)"
    }
}
