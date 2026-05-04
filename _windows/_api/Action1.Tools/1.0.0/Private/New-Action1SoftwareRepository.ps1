function New-Action1SoftwareRepository {
    <#
    .SYNOPSIS
        Creates a new software repository in Action1.

    .DESCRIPTION
        Creates a custom software repository with the specified properties.

    .PARAMETER OrganizationId
        The organization ID (or "all" for enterprise-wide).

    .PARAMETER Name
        The repository name.

    .PARAMETER Vendor
        The vendor/publisher name.

    .PARAMETER Description
        Description of the software.

    .PARAMETER InternalNotes
        Internal notes (optional).

    .PARAMETER Platform
        The platform: Windows, Mac, or Linux.

    .OUTPUTS
        Returns the created repository object with its ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationId,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Vendor,

        [Parameter()]
        [string]$Description = "",

        [Parameter()]
        [string]$InternalNotes = "",

        [Parameter(Mandatory)]
        [ValidateSet('Windows', 'Mac', 'Linux')]
        [string]$Platform
    )

    Write-Action1Log "Creating software repository: $Name" -Level INFO

    $token = Get-Action1AccessToken
    $uri = "$script:Action1BaseUri/software-repository/$OrganizationId"

    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }

    $body = @{
        name           = $Name
        vendor         = $Vendor
        description    = $Description
        internal_notes = $InternalNotes
        platform       = $Platform
    } | ConvertTo-Json -Depth 5

    # TRACE: Log full request details
    Write-Action1Log "========== REQUEST ==========" -Level TRACE
    Write-Action1Log "POST $uri" -Level TRACE
    Write-Action1Log "Request Headers:" -Level TRACE
    Write-Action1Log "  Authorization: Bearer ***MASKED***" -Level TRACE
    Write-Action1Log "  Content-Type: $($headers['Content-Type'])" -Level TRACE
    Write-Action1Log "  Accept: $($headers['Accept'])" -Level TRACE
    Write-Action1Log "Request Body:" -Level TRACE
    Write-Action1Log $body -Level TRACE
    Write-Action1Log "=============================" -Level TRACE

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $webResponse = Invoke-WebRequest -Uri $uri -Method POST -Headers $headers -Body $body -ErrorAction Stop
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

        if (-not $response.id) {
            throw "Repository creation returned no ID"
        }

        Write-Action1Log "Created repository: $Name (ID: $($response.id))" -Level INFO
        return $response
    }
    catch {
        Write-Action1Log "Failed to create repository" -Level ERROR -ErrorRecord $_
        throw
    }
}
