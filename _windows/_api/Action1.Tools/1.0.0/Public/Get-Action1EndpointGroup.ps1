function Get-Action1EndpointGroup {
    <#
    .SYNOPSIS
        Retrieves endpoint groups from Action1.

    .DESCRIPTION
        Lists endpoint groups for an organization. If no OrganizationId is provided,
        prompts user to select from available organizations.

    .PARAMETER OrganizationId
        Action1 organization ID. If not specified, prompts user to select.

    .PARAMETER GroupId
        Specific group ID to retrieve details for.

    .PARAMETER Name
        Filter groups by name.

    .EXAMPLE
        Get-Action1EndpointGroup
        # Interactive selection of organization then lists groups

    .EXAMPLE
        Get-Action1EndpointGroup -OrganizationId "org123" -Name "Servers"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$GroupId,

        [Parameter()]
        [string]$Name
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

        # If specific group requested
        if ($GroupId) {
            $group = Invoke-Action1ApiRequest `
                -Endpoint "endpoints/groups/$OrganizationId/$GroupId" `
                -Method GET
            return $group
        }

        # List all groups
        Write-Action1Log "Fetching endpoint groups for organization $OrganizationId..." -Level INFO
        $response = Invoke-Action1ApiRequest `
            -Endpoint "endpoints/groups/$OrganizationId`?limit=100" `
            -Method GET

        $groups = if ($response.items) { $response.items } else { @($response) }

        if ($Name) {
            $groups = $groups | Where-Object { $_.name -like "*$Name*" }
        }

        return $groups
    }
    catch {
        Write-Error "Failed to retrieve endpoint groups: $($_.Exception.Message)"
    }
}
