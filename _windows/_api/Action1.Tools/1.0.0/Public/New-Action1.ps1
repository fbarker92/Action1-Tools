function New-Action1 {
    <#
    .SYNOPSIS
        Generic function to create new Action1 resources.

    .DESCRIPTION
        Universal function to create any Action1 resource type. Similar to the
        official PSAction1 module's New-Action1 function.

    .PARAMETER Item
        The type of resource to create. Valid options:
        - EndpointGroup: Create a new endpoint group
        - Automation: Create a new automation/policy
        - Schedule: Create a new scheduled automation
        - App: Create a new software repository app
        - AppVersion: Create a new app version

    .PARAMETER OrganizationId
        Organization ID (required for most resources).

    .PARAMETER Data
        Hashtable containing the resource data to create.

    .EXAMPLE
        New-Action1 -Item EndpointGroup -OrganizationId "org123" -Data @{
            name = "Windows Servers"
            description = "All Windows Server endpoints"
        }

    .EXAMPLE
        New-Action1 -Item App -OrganizationId "all" -Data @{
            name = "My Application"
            vendor = "My Company"
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('EndpointGroup', 'Automation', 'Schedule', 'App', 'AppVersion')]
        [string]$Item,

        [Parameter()]
        [string]$OrganizationId,

        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    # Determine endpoint based on item type
    $endpoint = switch ($Item) {
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
            "endpoints/groups/$OrganizationId"
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
            "policies/$OrganizationId"
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
            "policies/schedules/$OrganizationId"
        }
        'App' {
            $orgPart = if ($OrganizationId) { $OrganizationId } else { "all" }
            "software-repository/$orgPart"
        }
        'AppVersion' {
            if (-not $Data.package_id) { throw "Data must include 'package_id' for AppVersion." }
            $orgPart = if ($OrganizationId) { $OrganizationId } else { "all" }
            "software-repository/$orgPart/$($Data.package_id)/versions"
        }
    }

    try {
        Write-Action1Log "Creating new $Item..." -Level INFO
        $response = Invoke-Action1ApiRequest -Endpoint $endpoint -Method POST -Body $Data
        Write-Action1Log "Created $Item successfully" -Level INFO
        return $response
    }
    catch {
        Write-Error "Failed to create $Item`: $($_.Exception.Message)"
    }
}
