function Remove-Action1AppRepo {
    <#
    .SYNOPSIS
        Removes an entire software repository from Action1.

    .DESCRIPTION
        Interactively selects and deletes an entire software repository package
        from Action1, including all versions and files.

    .PARAMETER OrganizationId
        Action1 organization ID. If not provided, prompts for selection.

    .PARAMETER PackageId
        Package ID to remove. If not provided, prompts for selection.

    .PARAMETER Force
        Skips confirmation prompt.

    .EXAMPLE
        Remove-Action1AppRepo
        # Interactive mode - prompts for org and repo selection

    .EXAMPLE
        Remove-Action1AppRepo -OrganizationId "all" -PackageId "pkg123" -Force
        # Direct removal without prompts
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$PackageId,

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

            Write-Host "`nSelect Repository to Delete:" -ForegroundColor Cyan
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

        # Get full repo info for confirmation
        $repoInfo = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId/$PackageId`?fields=*" `
            -Method GET

        $versionCount = if ($repoInfo.versions) { $repoInfo.versions.Count } else { 0 }
        $confirmMsg = "repository '$($repoInfo.name)' ($versionCount versions)"

        if ($Force -or $PSCmdlet.ShouldProcess($confirmMsg, "Remove")) {
            if (-not $Force) {
                Write-Host "`n⚠ WARNING: This will permanently delete the entire repository!" -ForegroundColor Red
                Write-Host "  Repository: $($repoInfo.name)" -ForegroundColor White
                Write-Host "  Vendor: $($repoInfo.vendor)" -ForegroundColor White
                Write-Host "  Versions: $versionCount" -ForegroundColor White
                Write-Host "`nAll versions and uploaded files will be permanently deleted." -ForegroundColor Red
                $confirm = Read-Host "Type 'DELETE' to confirm"
                if ($confirm -ne 'DELETE') {
                    Write-Host "Operation cancelled." -ForegroundColor Yellow
                    return
                }
            }

            Write-Host "`nDeleting repository..." -ForegroundColor Yellow
            Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId/$PackageId" `
                -Method DELETE

            Write-Host "✓ Repository '$($repoInfo.name)' and all versions removed successfully" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to remove repository: $($_.Exception.Message)"
    }
}
