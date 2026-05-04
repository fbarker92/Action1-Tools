function Get-Action1 {
    <#
    .SYNOPSIS
        Generic retrieval function for Action1 API resources.

    .DESCRIPTION
        Universal function to retrieve any Action1 resource type. Similar to the
        official PSAction1 module's Get-Action1 function, providing a single entry
        point for all data retrieval operations.

        Supports pagination automatically and can return raw JSON or PowerShell objects.

    .PARAMETER Query
        The type of resource to query. Valid options:
        - Organizations: List all organizations
        - Endpoints: List endpoints in an organization
        - EndpointGroups: List endpoint groups
        - Automations: List automations/policies
        - Schedules: List scheduled automations
        - Scripts: List scripts
        - Apps: List software repository apps
        - AppVersions: List app versions
        - Vulnerabilities: List vulnerabilities
        - MissingPatches: List missing patches
        - InstalledSoftware: List installed software
        - InstalledUpdates: List installed updates
        - Reports: List reports
        - ReportData: Get report data

    .PARAMETER OrganizationId
        Organization ID (required for most queries except Organizations).

    .PARAMETER Id
        Specific resource ID to retrieve details for.

    .PARAMETER Filter
        Additional filter parameters as a hashtable.

    .PARAMETER Limit
        Maximum number of results to return per page. Default is 100.

    .PARAMETER All
        Retrieve all pages of results (may be slow for large datasets).

    .PARAMETER Raw
        Return the raw API response instead of just the items.

    .EXAMPLE
        Get-Action1 -Query Organizations
        # List all organizations

    .EXAMPLE
        Get-Action1 -Query Endpoints -OrganizationId "org123"
        # List all endpoints in organization

    .EXAMPLE
        Get-Action1 -Query Vulnerabilities -OrganizationId "org123" -All
        # Get all vulnerabilities with pagination

    .EXAMPLE
        Get-Action1 -Query EndpointGroups -OrganizationId "org123" -Id "group456"
        # Get specific endpoint group

    .EXAMPLE
        Get-Action1 -Query InstalledSoftware -OrganizationId "org123" -Filter @{endpoint_id = "ep789"}
        # Get installed software for specific endpoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'Organizations',
            'Endpoints',
            'EndpointGroups',
            'Automations',
            'Schedules',
            'Scripts',
            'Apps',
            'AppVersions',
            'Vulnerabilities',
            'MissingPatches',
            'InstalledSoftware',
            'InstalledUpdates',
            'Reports',
            'ReportData'
        )]
        [string]$Query,

        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$Id,

        [Parameter()]
        [hashtable]$Filter,

        [Parameter()]
        [int]$Limit = 100,

        [Parameter()]
        [switch]$All,

        [Parameter()]
        [switch]$Raw
    )

    # Build endpoint URL based on query type
    $endpoint = switch ($Query) {
        'Organizations' { 'organizations' }
        'Endpoints' {
            if (-not $OrganizationId) {
                if ($script:Interactive) {
                    $selectedOrg = Select-Action1Organization -IncludeAll $false
                    if (-not $selectedOrg) { throw "No organization selected." }
                    $OrganizationId = $selectedOrg.Id
                } else {
                    throw "OrganizationId is required for Endpoints query."
                }
            }
            if ($Id) { "endpoints/$OrganizationId/$Id" }
            else { "endpoints/$OrganizationId" }
        }
        'EndpointGroups' {
            if (-not $OrganizationId) {
                if ($script:Interactive) {
                    $selectedOrg = Select-Action1Organization -IncludeAll $false
                    if (-not $selectedOrg) { throw "No organization selected." }
                    $OrganizationId = $selectedOrg.Id
                } else {
                    throw "OrganizationId is required for EndpointGroups query."
                }
            }
            if ($Id) { "endpoints/groups/$OrganizationId/$Id" }
            else { "endpoints/groups/$OrganizationId" }
        }
        'Automations' {
            if (-not $OrganizationId) {
                if ($script:Interactive) {
                    $selectedOrg = Select-Action1Organization -IncludeAll $false
                    if (-not $selectedOrg) { throw "No organization selected." }
                    $OrganizationId = $selectedOrg.Id
                } else {
                    throw "OrganizationId is required for Automations query."
                }
            }
            if ($Id) { "policies/$OrganizationId/policies/$Id" }
            else { "policies/$OrganizationId" }
        }
        'Schedules' {
            if (-not $OrganizationId) {
                if ($script:Interactive) {
                    $selectedOrg = Select-Action1Organization -IncludeAll $false
                    if (-not $selectedOrg) { throw "No organization selected." }
                    $OrganizationId = $selectedOrg.Id
                } else {
                    throw "OrganizationId is required for Schedules query."
                }
            }
            if ($Id) { "policies/schedules/$OrganizationId/$Id" }
            else { "policies/schedules/$OrganizationId" }
        }
        'Scripts' {
            if (-not $OrganizationId) {
                if ($script:Interactive) {
                    $selectedOrg = Select-Action1Organization -IncludeAll $false
                    if (-not $selectedOrg) { throw "No organization selected." }
                    $OrganizationId = $selectedOrg.Id
                } else {
                    throw "OrganizationId is required for Scripts query."
                }
            }
            if ($Id) { "scripts/$OrganizationId/$Id" }
            else { "scripts/$OrganizationId" }
        }
        'Apps' {
            if ($Id) { "apps/$Id" }
            else { "apps" }
        }
        'AppVersions' {
            if (-not $Id) { throw "App Id is required for AppVersions query." }
            "apps/$Id/versions"
        }
        'Vulnerabilities' {
            if (-not $OrganizationId) {
                if ($script:Interactive) {
                    $selectedOrg = Select-Action1Organization -IncludeAll $false
                    if (-not $selectedOrg) { throw "No organization selected." }
                    $OrganizationId = $selectedOrg.Id
                } else {
                    throw "OrganizationId is required for Vulnerabilities query."
                }
            }
            "data/$OrganizationId/vulnerabilities"
        }
        'MissingPatches' {
            if (-not $OrganizationId) {
                if ($script:Interactive) {
                    $selectedOrg = Select-Action1Organization -IncludeAll $false
                    if (-not $selectedOrg) { throw "No organization selected." }
                    $OrganizationId = $selectedOrg.Id
                } else {
                    throw "OrganizationId is required for MissingPatches query."
                }
            }
            "data/$OrganizationId/missing_patches"
        }
        'InstalledSoftware' {
            if (-not $OrganizationId) {
                if ($script:Interactive) {
                    $selectedOrg = Select-Action1Organization -IncludeAll $false
                    if (-not $selectedOrg) { throw "No organization selected." }
                    $OrganizationId = $selectedOrg.Id
                } else {
                    throw "OrganizationId is required for InstalledSoftware query."
                }
            }
            "data/$OrganizationId/installed_software"
        }
        'InstalledUpdates' {
            if (-not $OrganizationId) {
                if ($script:Interactive) {
                    $selectedOrg = Select-Action1Organization -IncludeAll $false
                    if (-not $selectedOrg) { throw "No organization selected." }
                    $OrganizationId = $selectedOrg.Id
                } else {
                    throw "OrganizationId is required for InstalledUpdates query."
                }
            }
            "data/$OrganizationId/installed_updates"
        }
        'Reports' {
            if (-not $OrganizationId) {
                if ($script:Interactive) {
                    $selectedOrg = Select-Action1Organization -IncludeAll $false
                    if (-not $selectedOrg) { throw "No organization selected." }
                    $OrganizationId = $selectedOrg.Id
                } else {
                    throw "OrganizationId is required for Reports query."
                }
            }
            if ($Id) { "reports/$OrganizationId/$Id" }
            else { "reports/$OrganizationId" }
        }
        'ReportData' {
            if (-not $OrganizationId) {
                if ($script:Interactive) {
                    $selectedOrg = Select-Action1Organization -IncludeAll $false
                    if (-not $selectedOrg) { throw "No organization selected." }
                    $OrganizationId = $selectedOrg.Id
                } else {
                    throw "OrganizationId is required for ReportData query."
                }
            }
            if (-not $Id) { throw "Report Id is required for ReportData query." }
            "reports/$OrganizationId/$Id/data"
        }
    }

    try {
        Write-Action1Log "Querying $Query..." -Level INFO

        # Build query parameters
        $queryParams = @{ limit = $Limit }
        if ($Filter) {
            foreach ($key in $Filter.Keys) {
                $queryParams[$key] = $Filter[$key]
            }
        }

        $allResults = @()
        $nextPage = $null

        do {
            # Add pagination cursor if continuing
            if ($nextPage) {
                $queryParams['page'] = $nextPage
            }

            # Build query string
            $queryString = ($queryParams.GetEnumerator() | ForEach-Object {
                "$($_.Key)=$([uri]::EscapeDataString($_.Value))"
            }) -join '&'

            $fullEndpoint = if ($queryString) { "$endpoint`?$queryString" } else { $endpoint }

            $response = Invoke-Action1ApiRequest -Endpoint $fullEndpoint -Method GET

            if ($Raw) {
                return $response
            }

            # Extract items
            $items = if ($response.items) { $response.items } else { @($response) }
            $allResults += $items

            # Check for next page
            $nextPage = $response.next_page
            if (-not $All) { $nextPage = $null }

        } while ($nextPage)

        Write-Action1Log "Retrieved $($allResults.Count) $Query items" -Level INFO
        return $allResults
    }
    catch {
        Write-Error "Failed to retrieve $Query`: $($_.Exception.Message)"
    }
}
