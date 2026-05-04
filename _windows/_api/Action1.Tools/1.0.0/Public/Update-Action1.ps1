function Update-Action1 {
    <#
    .SYNOPSIS
        Generic function to update or delete Action1 resources.

    .DESCRIPTION
        Universal function to modify or delete any Action1 resource type. Similar to
        the official PSAction1 module's Update-Action1 function.

        Includes confirmation prompts for destructive operations.

    .PARAMETER Action
        The action to perform: Modify, ModifyMembers, or Delete.

    .PARAMETER Type
        The type of resource to update. Valid options:
        - EndpointGroup
        - Automation
        - Schedule
        - App
        - AppVersion

    .PARAMETER Id
        The resource ID to update/delete.

    .PARAMETER OrganizationId
        Organization ID (required for most resources).

    .PARAMETER Data
        Hashtable containing the data to update (for Modify actions).

    .PARAMETER Force
        Skip confirmation prompts for destructive operations.

    .EXAMPLE
        Update-Action1 -Action Modify -Type EndpointGroup -Id "grp123" `
            -OrganizationId "org456" -Data @{ description = "Updated description" }

    .EXAMPLE
        Update-Action1 -Action Delete -Type App -Id "app789" -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Modify', 'ModifyMembers', 'Delete')]
        [string]$Action,

        [Parameter(Mandatory)]
        [ValidateSet('EndpointGroup', 'Automation', 'Schedule', 'App', 'AppVersion')]
        [string]$Type,

        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [hashtable]$Data,

        [Parameter()]
        [switch]$Force
    )

    # Build endpoint
    $endpoint = switch ($Type) {
        'EndpointGroup' {
            if (-not $OrganizationId) {
                if ($script:Interactive) {
                    $selectedOrg = Select-Action1Organization -IncludeAll $false
                    if (-not $selectedOrg) { throw "No organization selected." }
                    $OrganizationId = $selectedOrg.Id
                } else {
                    throw "OrganizationId is required for EndpointGroup."
                }
            }
            "endpoints/groups/$OrganizationId/$Id"
        }
        'Automation' {
            if (-not $OrganizationId) {
                if ($script:Interactive) {
                    $selectedOrg = Select-Action1Organization -IncludeAll $false
                    if (-not $selectedOrg) { throw "No organization selected." }
                    $OrganizationId = $selectedOrg.Id
                } else {
                    throw "OrganizationId is required for Automation."
                }
            }
            "policies/$OrganizationId/policies/$Id"
        }
        'Schedule' {
            if (-not $OrganizationId) {
                if ($script:Interactive) {
                    $selectedOrg = Select-Action1Organization -IncludeAll $false
                    if (-not $selectedOrg) { throw "No organization selected." }
                    $OrganizationId = $selectedOrg.Id
                } else {
                    throw "OrganizationId is required for Schedule."
                }
            }
            "policies/schedules/$OrganizationId/$Id"
        }
        'App' {
            $orgPart = if ($OrganizationId) { $OrganizationId } else { "all" }
            "software-repository/$orgPart/$Id"
        }
        'AppVersion' {
            if (-not $Data -or -not $Data.package_id) { throw "Data must include 'package_id' for AppVersion." }
            $orgPart = if ($OrganizationId) { $OrganizationId } else { "all" }
            "software-repository/$orgPart/$($Data.package_id)/versions/$Id"
        }
    }

    # Determine HTTP method
    $method = switch ($Action) {
        'Modify' { 'PATCH' }
        'ModifyMembers' { 'PATCH' }
        'Delete' { 'DELETE' }
    }

    try {
        # Confirmation for delete
        if ($Action -eq 'Delete' -and -not $Force) {
            if (-not $PSCmdlet.ShouldProcess($Id, "Delete $Type")) {
                Write-Host "Operation cancelled." -ForegroundColor Yellow
                return
            }
        }

        Write-Action1Log "$Action $Type $Id..." -Level INFO

        $params = @{
            Endpoint = $endpoint
            Method = $method
        }
        if ($Data -and $Action -ne 'Delete') {
            $params['Body'] = $Data
        }

        $response = Invoke-Action1ApiRequest @params
        Write-Action1Log "$Action completed successfully" -Level INFO
        return $response
    }
    catch {
        Write-Error "Failed to $Action $Type`: $($_.Exception.Message)"
    }
}
