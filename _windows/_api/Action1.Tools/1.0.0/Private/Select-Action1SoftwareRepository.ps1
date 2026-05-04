function Select-Action1SoftwareRepository {
    <#
    .SYNOPSIS
        Interactively selects or creates a software repository.

    .DESCRIPTION
        Lists existing custom repositories and prompts the user to select one
        or create a new one. If DefaultName is provided and matches an existing
        repository, it will be auto-selected.

    .PARAMETER OrganizationId
        The organization ID (or "all" for enterprise-wide).

    .PARAMETER DefaultName
        Default name for creating a new repository. Also used for auto-matching.

    .PARAMETER DefaultVendor
        Default vendor for creating a new repository.

    .PARAMETER DefaultPlatform
        Default platform for creating a new repository.

    .PARAMETER AutoSelect
        If true and DefaultName matches an existing repo, auto-select it without prompting.

    .OUTPUTS
        Returns a hashtable with Id and IsNew properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationId,

        [Parameter()]
        [string]$DefaultName,

        [Parameter()]
        [string]$DefaultVendor,

        [Parameter()]
        [ValidateSet('Windows', 'Mac', 'Linux')]
        [string]$DefaultPlatform = 'Windows',

        [Parameter()]
        [switch]$AutoSelect
    )

    $repos = Get-Action1SoftwareRepositories -OrganizationId $OrganizationId

    if ($repos.Count -eq 0) {
        Write-Host "`nNo custom repositories found. Creating new one..." -ForegroundColor Yellow

        $name = if ($DefaultName) { $DefaultName } else { Read-Host "Repository name" }
        $vendor = if ($DefaultVendor) { $DefaultVendor } else { Read-Host "Vendor name" }

        $newRepo = New-Action1SoftwareRepository `
            -OrganizationId $OrganizationId `
            -Name $name `
            -Vendor $vendor `
            -Platform $DefaultPlatform

        return @{
            Id    = $newRepo.id
            IsNew = $true
        }
    }

    # Try to auto-match by name if DefaultName is provided
    if ($DefaultName) {
        $matchedRepo = $repos | Where-Object { $_.name -eq $DefaultName } | Select-Object -First 1
        if ($matchedRepo) {
            Write-Host "`nAuto-matched repository: $($matchedRepo.name) ($($matchedRepo.vendor))" -ForegroundColor Green
            return @{
                Id    = $matchedRepo.id
                IsNew = $false
            }
        }
    }

    Write-Host "`nExisting Custom Repositories:" -ForegroundColor Cyan
    Write-Host "  [0] Create new repository" -ForegroundColor Yellow
    for ($i = 0; $i -lt $repos.Count; $i++) {
        $repo = $repos[$i]
        Write-Host "  [$($i + 1)] $($repo.name) ($($repo.vendor)) - $($repo.platform)"
    }

    $maxIndex = $repos.Count
    do {
        $selection = Read-Host "`nEnter selection (0-$maxIndex)"
        $selNum = -1
        if (-not [int]::TryParse($selection, [ref]$selNum) -or ($selNum -lt 0 -or $selNum -gt $maxIndex)) {
            Write-Host "Invalid selection. Please enter a number between 0 and $maxIndex." -ForegroundColor Red
            continue
        }
        break
    } while ($true)

    if ($selNum -eq 0) {
        # Create new repository
        $name = if ($DefaultName) { $DefaultName } else { Read-Host "Repository name" }
        $vendor = if ($DefaultVendor) { $DefaultVendor } else { Read-Host "Vendor name" }

        $newRepo = New-Action1SoftwareRepository `
            -OrganizationId $OrganizationId `
            -Name $name `
            -Vendor $vendor `
            -Platform $DefaultPlatform

        return @{
            Id    = $newRepo.id
            IsNew = $true
        }
    }
    else {
        $selectedRepo = $repos[$selNum - 1]
        Write-Host "Selected: $($selectedRepo.name)" -ForegroundColor Green
        return @{
            Id    = $selectedRepo.id
            IsNew = $false
        }
    }
}
