function Get-Action1Automation {
    <#
    .SYNOPSIS
        Retrieves automations (policies) from Action1.

    .DESCRIPTION
        Lists automations for an organization with interactive drill-down.
        If no OrganizationId is provided, prompts user to select from available organizations.

    .PARAMETER OrganizationId
        Action1 organization ID. If not specified, prompts user to select.

    .PARAMETER AutomationId
        Specific automation ID to retrieve details for.

    .PARAMETER Name
        Filter automations by name.

    .PARAMETER NoInteractive
        Disable interactive mode. By default, allows selecting an automation for details.

    .EXAMPLE
        Get-Action1Automation
        # Interactive selection of organization and automation

    .EXAMPLE
        Get-Action1Automation -OrganizationId "org123" -NoInteractive
        # Returns all automations without prompts
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$AutomationId,

        [Parameter()]
        [string]$Name,

        [Parameter()]
        [switch]$NoInteractive
    )

    try {
        # If no OrganizationId provided, prompt for selection
        if (-not $OrganizationId) {
            $selectedOrg = Select-Action1Organization -IncludeAll $false
            if (-not $selectedOrg) {
                throw "No organization selected."
            }
            $OrganizationId = $selectedOrg.Id
        }

        # If specific automation requested
        if ($AutomationId) {
            Write-Action1Log "Fetching automation details: $AutomationId" -Level INFO
            $automation = Invoke-Action1ApiRequest `
                -Endpoint "policies/schedules/$OrganizationId/$AutomationId" `
                -Method GET
            return $automation
        }

        # List all automations
        Write-Action1Log "Fetching automations for organization $OrganizationId..." -Level INFO
        $response = Invoke-Action1ApiRequest `
            -Endpoint "policies/schedules/$OrganizationId`?limit=100" `
            -Method GET

        $automations = if ($response.items) { $response.items } else { @($response) }

        if ($Name) {
            $automations = $automations | Where-Object { $_.name -like "*$Name*" }
        }

        # If NoInteractive, just return the list
        if ($NoInteractive) {
            return $automations
        }

        # Interactive mode - allow selecting an automation for details
        if ($automations.Count -eq 0) {
            Write-Host "`nNo automations found." -ForegroundColor Yellow
            return @()
        }

        Write-Host "`nSelect Automation:" -ForegroundColor Cyan
        Write-Host "  [0] Return all automations (no drill-down)"
        for ($i = 0; $i -lt $automations.Count; $i++) {
            $auto = $automations[$i]
            $status = if ($auto.enabled) { "[Enabled]" } else { "[Disabled]" }
            $trigger = if ($auto.trigger_type) { "($($auto.trigger_type))" } else { "" }
            Write-Host "  [$($i + 1)] $($auto.name) $status $trigger"
        }

        $autoSelection = Read-Host "`nEnter selection (0-$($automations.Count))"
        $autoNum = [int]$autoSelection

        if ($autoNum -eq 0) {
            return $automations
        }

        if ($autoNum -lt 1 -or $autoNum -gt $automations.Count) {
            throw "Invalid selection."
        }

        $selectedAutomation = $automations[$autoNum - 1]
        Write-Host "Selected: $($selectedAutomation.name)" -ForegroundColor Green

        # Fetch full automation details
        Write-Action1Log "Fetching automation details..." -Level INFO
        $automationDetails = Invoke-Action1ApiRequest `
            -Endpoint "policies/schedules/$OrganizationId/$($selectedAutomation.id)" `
            -Method GET

        return $automationDetails
    }
    catch {
        Write-Error "Failed to retrieve automations: $($_.Exception.Message)"
    }
}
