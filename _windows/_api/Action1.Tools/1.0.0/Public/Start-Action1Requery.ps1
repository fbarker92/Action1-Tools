function Start-Action1Requery {
    <#
    .SYNOPSIS
        Triggers a data refresh for endpoints.

    .DESCRIPTION
        Requests Action1 to re-query endpoint data including installed software,
        updates, and report data. Similar to the official PSAction1 module's
        Start-Action1Requery function.

    .PARAMETER Type
        The type of data to refresh:
        - ReportData: Refresh report data
        - InstalledSoftware: Refresh installed software inventory
        - InstalledUpdates: Refresh installed updates inventory

    .PARAMETER OrganizationId
        Organization ID to refresh data for.

    .PARAMETER EndpointId
        Optional specific endpoint ID. If not specified, refreshes all endpoints.

    .EXAMPLE
        Start-Action1Requery -Type InstalledSoftware -OrganizationId "org123"
        # Refresh software inventory for all endpoints in organization

    .EXAMPLE
        Start-Action1Requery -Type InstalledUpdates -OrganizationId "org123" -EndpointId "ep456"
        # Refresh updates for specific endpoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ReportData', 'InstalledSoftware', 'InstalledUpdates')]
        [string]$Type,

        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$EndpointId
    )

    if (-not $OrganizationId) {
        if ($script:Interactive) {
            $selectedOrg = Select-Action1Organization -IncludeAll $false
            if (-not $selectedOrg) { throw "No organization selected." }
            $OrganizationId = $selectedOrg.Id
        } else {
            throw "OrganizationId is required."
        }
    }

    $endpoint = switch ($Type) {
        'ReportData' { "data/$OrganizationId/requery/reports" }
        'InstalledSoftware' { "data/$OrganizationId/requery/installed_software" }
        'InstalledUpdates' { "data/$OrganizationId/requery/installed_updates" }
    }

    $body = @{}
    if ($EndpointId) {
        $body['endpoint_id'] = $EndpointId
    }

    try {
        Write-Action1Log "Triggering $Type requery for organization $OrganizationId..." -Level INFO
        $response = Invoke-Action1ApiRequest -Endpoint $endpoint -Method POST -Body $body
        Write-Host "Requery initiated successfully. Data will be refreshed shortly." -ForegroundColor Green
        return $response
    }
    catch {
        Write-Error "Failed to trigger requery: $($_.Exception.Message)"
    }
}
