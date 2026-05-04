function Select-Action1Organization {
    <#
    .SYNOPSIS
        Prompts user to select an Action1 organization.

    .DESCRIPTION
        Fetches available organizations from the API and displays an interactive
        selection menu. Supports "All" option for enterprise-wide scope.

    .PARAMETER IncludeAll
        If specified, includes "All (Enterprise-wide)" as the first option.
        Defaults to $true.

    .PARAMETER Prompt
        Custom prompt text. Defaults to "Select Organization".

    .OUTPUTS
        Returns a hashtable with 'Id' and 'Name' properties, or $null if cancelled.

    .EXAMPLE
        $org = Select-Action1Organization
        # Returns @{ Id = "org-123"; Name = "Contoso Corp" }

    .EXAMPLE
        $org = Select-Action1Organization -IncludeAll:$false
        # Only shows specific organizations, no "All" option
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [bool]$IncludeAll = $true,

        [Parameter()]
        [string]$Prompt = "Select Organization"
    )

    try {
        Write-Host "`nFetching available organizations..." -ForegroundColor Gray
        $orgsResponse = Invoke-Action1ApiRequest -Endpoint "organizations" -Method GET

        # Handle both array and items-wrapped responses
        $orgs = if ($orgsResponse.items) { @($orgsResponse.items) } else { @($orgsResponse) }

        if ($orgs.Count -eq 0) {
            if ($IncludeAll) {
                Write-Host "No specific organizations found. Using 'all' scope." -ForegroundColor Yellow
                return @{ Id = "all"; Name = "All (Enterprise-wide)" }
            } else {
                Write-Warning "No organizations found."
                return $null
            }
        }

        Write-Host "`n${Prompt}:" -ForegroundColor Cyan

        if ($IncludeAll) {
            Write-Host "  [0] All (Enterprise-wide)"
        }

        for ($i = 0; $i -lt $orgs.Count; $i++) {
            Write-Host "  [$($i + 1)] $($orgs[$i].name)"
        }

        $maxSelection = $orgs.Count
        $selectionPrompt = if ($IncludeAll) { "0-$maxSelection" } else { "1-$maxSelection" }
        $selection = Read-Host "`nEnter selection ($selectionPrompt)"

        if (-not $selection) {
            if ($IncludeAll) {
                Write-Host "Selected: All (Enterprise-wide)" -ForegroundColor Green
                return @{ Id = "all"; Name = "All (Enterprise-wide)" }
            } else {
                return $null
            }
        }

        $selNum = [int]$selection

        if ($IncludeAll -and $selNum -eq 0) {
            Write-Host "Selected: All (Enterprise-wide)" -ForegroundColor Green
            return @{ Id = "all"; Name = "All (Enterprise-wide)" }
        }

        $orgIndex = $selNum - 1
        if ($orgIndex -ge 0 -and $orgIndex -lt $orgs.Count) {
            $selectedOrg = $orgs[$orgIndex]
            Write-Host "Selected: $($selectedOrg.name)" -ForegroundColor Green
            return @{ Id = $selectedOrg.id; Name = $selectedOrg.name }
        }

        Write-Host "Invalid selection." -ForegroundColor Yellow
        if ($IncludeAll) {
            Write-Host "Using 'all' scope." -ForegroundColor Yellow
            return @{ Id = "all"; Name = "All (Enterprise-wide)" }
        }
        return $null
    }
    catch {
        Write-Action1Log "Failed to fetch organizations: $_" -Level WARN
        $manualId = Read-Host "Enter Action1 Organization ID manually (or 'all' for all organizations)"
        if (-not $manualId) { $manualId = "all" }
        return @{ Id = $manualId; Name = $manualId }
    }
}
