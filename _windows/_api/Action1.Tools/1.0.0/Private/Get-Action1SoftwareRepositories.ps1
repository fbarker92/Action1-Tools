function Get-Action1SoftwareRepositories {
    <#
    .SYNOPSIS
        Lists custom software repositories from Action1.

    .DESCRIPTION
        Retrieves a list of custom software repositories for the specified organization.

    .PARAMETER OrganizationId
        The organization ID (or "all" for enterprise-wide).

    .OUTPUTS
        Returns an array of repository objects with id, name, vendor, platform properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationId
    )

    Write-Action1Log "Fetching custom software repositories..." -Level INFO

    $token = Get-Action1AccessToken
    $uri = "$script:Action1BaseUri/software-repository/$OrganizationId`?custom=yes&builtin=no&limit=100"

    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }

    # TRACE: Log full request details
    Write-Action1Log "========== REQUEST ==========" -Level TRACE
    Write-Action1Log "GET $uri" -Level TRACE
    Write-Action1Log "Request Headers:" -Level TRACE
    Write-Action1Log "  Authorization: Bearer ***MASKED***" -Level TRACE
    Write-Action1Log "  Content-Type: $($headers['Content-Type'])" -Level TRACE
    Write-Action1Log "  Accept: $($headers['Accept'])" -Level TRACE
    Write-Action1Log "=============================" -Level TRACE

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $webResponse = Invoke-WebRequest -Uri $uri -Method GET -Headers $headers -ErrorAction Stop
        $stopwatch.Stop()

        # TRACE: Log full response details
        Write-Action1Log "========== RESPONSE ==========" -Level TRACE
        Write-Action1Log "HTTP Status: $($webResponse.StatusCode) $($webResponse.StatusDescription)" -Level TRACE
        Write-Action1Log "Duration: $($stopwatch.ElapsedMilliseconds)ms" -Level TRACE
        Write-Action1Log "Response Headers:" -Level TRACE
        foreach ($headerName in $webResponse.Headers.Keys) {
            $headerValue = $webResponse.Headers[$headerName]
            if ($headerValue -is [array]) { $headerValue = $headerValue -join ', ' }
            Write-Action1Log "  $headerName`: $headerValue" -Level TRACE
        }
        Write-Action1Log "Content-Length: $($webResponse.Content.Length) bytes" -Level TRACE
        Write-Action1Log "Response Body:" -Level TRACE
        Write-Action1Log $webResponse.Content -Level TRACE
        Write-Action1Log "==============================" -Level TRACE

        $response = $webResponse.Content | ConvertFrom-Json
        $items = if ($response.items) { $response.items } else { @() }
        Write-Action1Log "Found $($items.Count) custom repositories" -Level INFO
        return $items
    }
    catch {
        Write-Action1Log "Failed to list repositories" -Level ERROR -ErrorRecord $_
        throw
    }
}
