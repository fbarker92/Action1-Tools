function Get-Action1AccessToken {
    <#
    .SYNOPSIS
        Obtains an OAuth2 access token from the Action1 API.
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    # Check if we have a valid token already
    if (-not $Force -and $script:Action1AccessToken -and $script:Action1TokenExpiry -and (Get-Date) -lt $script:Action1TokenExpiry) {
        Write-Action1Log "Using cached access token (expires: $($script:Action1TokenExpiry))" -Level DEBUG
        return $script:Action1AccessToken
    }

    if (-not $script:Action1ClientId -or -not $script:Action1ClientSecret) {
        Write-Action1Log "API credentials not configured" -Level ERROR
        throw "Action1 API credentials not set. Please run Set-Action1ApiCredentials first."
    }

    if (-not $script:Action1BaseUri) {
        Write-Action1Log "API base URI not configured" -Level ERROR
        throw "Action1 API base URI not set. Please run Set-Action1ApiCredentials first."
    }

    Write-Action1Log "Requesting OAuth2 access token..." -Level INFO

    $tokenUrl = "$($script:Action1BaseUri)/oauth2/token"
    $body = @{
        client_id     = $script:Action1ClientId
        client_secret = $script:Action1ClientSecret
    }

    # TRACE logging for token request (mask sensitive data)
    Write-Action1Log "Token request URL: $tokenUrl" -Level TRACE
    Write-Action1Log "Token request body" -Level TRACE -Data @{
        client_id     = $script:Action1ClientId
        client_secret = "***MASKED***"
    }

    try {
        $bodyJson = $body | ConvertTo-Json

        # TRACE: Log full request details
        Write-Action1Log "========== TOKEN REQUEST ==========" -Level TRACE
        Write-Action1Log "POST $tokenUrl" -Level TRACE
        Write-Action1Log "Content-Type: application/json" -Level TRACE
        Write-Action1Log "Request Body: $($bodyJson -replace $script:Action1ClientSecret, '***MASKED***')" -Level TRACE
        Write-Action1Log "===================================" -Level TRACE

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Use Invoke-WebRequest for full HTTP details
        $webResponse = Invoke-WebRequest -Uri $tokenUrl -Method POST -Body $bodyJson -ContentType 'application/json' -ErrorAction Stop

        $stopwatch.Stop()
        $statusCode = $webResponse.StatusCode
        $statusDescription = $webResponse.StatusDescription

        # TRACE: Log full response details
        Write-Action1Log "========== TOKEN RESPONSE ==========" -Level TRACE
        Write-Action1Log "HTTP Status: $statusCode $statusDescription" -Level TRACE
        Write-Action1Log "Duration: $($stopwatch.ElapsedMilliseconds)ms" -Level TRACE

        # Log response headers
        Write-Action1Log "Response Headers:" -Level TRACE
        foreach ($headerName in $webResponse.Headers.Keys) {
            $headerValue = $webResponse.Headers[$headerName]
            if ($headerValue -is [array]) { $headerValue = $headerValue -join ', ' }
            Write-Action1Log "  $headerName`: $headerValue" -Level TRACE
        }

        # Log content details (mask token in raw output)
        $contentType = if ($webResponse.Headers['Content-Type']) { $webResponse.Headers['Content-Type'] } else { 'unknown' }
        Write-Action1Log "Content-Type: $contentType" -Level TRACE
        Write-Action1Log "Content-Length: $($webResponse.Content.Length) bytes" -Level TRACE
        Write-Action1Log "Response Body (raw, token masked):" -Level TRACE
        $maskedContent = $webResponse.Content -replace '"access_token"\s*:\s*"[^"]+', '"access_token":"***MASKED***'
        Write-Action1Log $maskedContent -Level TRACE
        Write-Action1Log "====================================" -Level TRACE

        # Parse response
        $response = $webResponse.Content | ConvertFrom-Json

        Write-Action1Log "Token response (parsed, masked)" -Level TRACE -Data @{
            access_token = "***MASKED*** (length: $($response.access_token.Length))"
            expires_in   = $response.expires_in
            token_type   = $response.token_type
        }

        $script:Action1AccessToken = $response.access_token

        # Set token expiry (default to 1 hour if not provided, subtract 5 minutes for safety)
        $expiresIn = if ($response.expires_in) { $response.expires_in - 300 } else { 3300 }
        $script:Action1TokenExpiry = (Get-Date).AddSeconds($expiresIn)

        Write-Action1Log "Access token obtained successfully (expires in $expiresIn seconds)" -Level INFO
        return $script:Action1AccessToken
    }
    catch {
        Write-Action1Log "Failed to obtain access token" -Level ERROR -ErrorRecord $_

        # TRACE: Log error details
        if ($_.Exception.Response) {
            $errorResponse = $_.Exception.Response
            Write-Action1Log "========== TOKEN ERROR RESPONSE ==========" -Level TRACE
            Write-Action1Log "HTTP Status: $([int]$errorResponse.StatusCode) $($errorResponse.StatusCode)" -Level TRACE
            try {
                $reader = [System.IO.StreamReader]::new($errorResponse.GetResponseStream())
                $errorBody = $reader.ReadToEnd()
                $reader.Close()
                Write-Action1Log "Error Response Body:" -Level TRACE
                Write-Action1Log $errorBody -Level TRACE
            }
            catch {
                Write-Action1Log "Could not read error response body" -Level TRACE
            }
            Write-Action1Log "===========================================" -Level TRACE
        }

        throw "Authentication failed: $($_.Exception.Message)"
    }
}
