function Get-Action1RepositoryVersions {
    <#
    .SYNOPSIS
        Lists versions for a software repository.

    .DESCRIPTION
        Retrieves all versions for the specified software repository.

    .PARAMETER OrganizationId
        The organization ID (or "all" for enterprise-wide).

    .PARAMETER RepositoryId
        The software repository ID.

    .OUTPUTS
        Returns an array of version objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationId,

        [Parameter(Mandatory)]
        [string]$RepositoryId
    )

    Write-Action1Log "Fetching versions for repository $RepositoryId..." -Level INFO

    $token = Get-Action1AccessToken
    $uri = "$script:Action1BaseUri/software-repository/$OrganizationId/$RepositoryId/versions?limit=100"

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

        # Handle different response formats
        if ($response.type -eq 'Version') {
            # Single version object
            return @($response)
        }
        elseif ($response.items) {
            return $response.items
        }
        else {
            return @()
        }
    }
    catch {
        Write-Action1Log "Failed to list versions" -Level WARN -ErrorRecord $_
        return @()
    }
}
