function Initialize-Action1SoftwareRepoUpload {
    <#
    .SYNOPSIS
        Initializes a resumable upload session for Action1 software repository.

    .DESCRIPTION
        Sends a POST request to the upload endpoint with content metadata headers.
        Returns the upload URL from the X-Upload-Location header.

    .PARAMETER OrganizationId
        The organization ID (or "all" for enterprise-wide).

    .PARAMETER PackageId
        The software repository package ID.

    .PARAMETER VersionId
        The version ID to upload to.

    .PARAMETER Platform
        The platform identifier (e.g., Windows_64, Windows_32, Mac_AppleSilicon).

    .PARAMETER FileSize
        The total file size in bytes.

    .OUTPUTS
        Returns the upload URL to use for chunked uploads.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationId,

        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
        [string]$VersionId,

        [Parameter(Mandatory)]
        [string]$Platform,

        [Parameter(Mandatory)]
        [long]$FileSize
    )

    $token = Get-Action1AccessToken
    $uploadInitUrl = "$script:Action1BaseUri/software-repository/$OrganizationId/$PackageId/versions/$VersionId/upload?platform=$Platform"

    Write-Action1Log "Initializing upload session: $uploadInitUrl" -Level INFO
    Write-Action1Log "File size: $FileSize bytes, Platform: $Platform" -Level DEBUG

    $headers = @{
        'Authorization'           = "Bearer $token"
        'Content-Type'            = 'application/json'
        'Accept'                  = 'application/json'
        'X-Upload-Content-Type'   = 'application/octet-stream'
        'X-Upload-Content-Length' = $FileSize.ToString()
    }

    # TRACE: Log full request details
    Write-Action1Log "========== UPLOAD INIT REQUEST ==========" -Level TRACE
    Write-Action1Log "POST $uploadInitUrl" -Level TRACE
    Write-Action1Log "Request Headers:" -Level TRACE
    foreach ($headerName in $headers.Keys) {
        $headerValue = if ($headerName -eq 'Authorization') { "Bearer ***MASKED***" } else { $headers[$headerName] }
        Write-Action1Log "  $headerName`: $headerValue" -Level TRACE
    }
    Write-Action1Log "Request Body: (empty)" -Level TRACE
    Write-Action1Log "==========================================" -Level TRACE

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Use -SkipHttpErrorCheck to handle 308 responses (PowerShell 7+)
        $response = Invoke-WebRequest -Uri $uploadInitUrl -Method POST -Headers $headers -SkipHttpErrorCheck

        $stopwatch.Stop()
        $statusCode = $response.StatusCode
        $statusDescription = $response.StatusDescription

        # TRACE: Log full response details
        Write-Action1Log "========== UPLOAD INIT RESPONSE ==========" -Level TRACE
        Write-Action1Log "HTTP Status: $statusCode $statusDescription" -Level TRACE
        Write-Action1Log "Duration: $($stopwatch.ElapsedMilliseconds)ms" -Level TRACE
        Write-Action1Log "Response Headers:" -Level TRACE
        foreach ($headerName in $response.Headers.Keys) {
            $headerValue = $response.Headers[$headerName]
            if ($headerValue -is [array]) { $headerValue = $headerValue -join ', ' }
            Write-Action1Log "  $headerName`: $headerValue" -Level TRACE
        }
        $contentType = if ($response.Headers['Content-Type']) { $response.Headers['Content-Type'] } else { 'none' }
        Write-Action1Log "Content-Type: $contentType" -Level TRACE
        Write-Action1Log "Content-Length: $($response.Content.Length) bytes" -Level TRACE
        if ($response.Content) {
            Write-Action1Log "Response Body:" -Level TRACE
            Write-Action1Log $response.Content -Level TRACE
        }
        Write-Action1Log "===========================================" -Level TRACE

        Write-Action1Log "Upload init response status: $statusCode" -Level DEBUG

        if ($statusCode -ne 308) {
            Write-Action1Log "Upload init failed: expected 308, got $statusCode" -Level ERROR
            Write-Action1Log "Response: $($response.Content)" -Level ERROR
            throw "Upload initialization failed: expected HTTP 308, got $statusCode"
        }

        # Get the upload location from headers
        $uploadLocation = $response.Headers['X-Upload-Location']
        if (-not $uploadLocation) {
            $uploadLocation = $response.Headers['x-upload-location']
        }

        if (-not $uploadLocation) {
            Write-Action1Log "X-Upload-Location header missing from response" -Level ERROR
            Write-Action1Log "Available headers: $($response.Headers.Keys -join ', ')" -Level DEBUG
            throw "Upload initialization succeeded but X-Upload-Location header is missing"
        }

        # Handle array response (PowerShell may return headers as arrays)
        if ($uploadLocation -is [array]) {
            $uploadLocation = $uploadLocation[0]
        }

        # Normalize the upload URL
        $normalizedUrl = Get-UploadLocationUrl -BaseUri $script:Action1BaseUri -Location $uploadLocation

        Write-Action1Log "Upload URL obtained: $normalizedUrl" -Level INFO

        return $normalizedUrl
    }
    catch {
        Write-Action1Log "Upload initialization failed" -Level ERROR -ErrorRecord $_
        throw
    }
}
