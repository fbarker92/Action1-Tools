function Invoke-Action1ApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,
        
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'PATCH')]
        [string]$Method,
        
        [Parameter()]
        [hashtable]$Body,
        
        [Parameter()]
        [hashtable]$QueryParameters
    )
    
    $headers = Get-Action1Headers
    $uri = "$script:Action1BaseUri/$Endpoint"

    if ($QueryParameters) {
        $queryString = ($QueryParameters.GetEnumerator() | ForEach-Object {
            "$($_.Key)=$([uri]::EscapeDataString($_.Value))"
        }) -join '&'
        $uri = "$uri`?$queryString"
    }

    Write-Action1Log "Preparing API request: $Method $uri" -Level DEBUG

    # TRACE: Log complete request details
    Write-Action1Log "Request endpoint: $Endpoint" -Level TRACE
    Write-Action1Log "Request full URI: $uri" -Level TRACE
    Write-Action1Log "Request method: $Method" -Level TRACE
    if ($QueryParameters) {
        Write-Action1Log "Query parameters" -Level TRACE -Data $QueryParameters
    }

    $params = @{
        Uri = $uri
        Method = $Method
        Headers = $headers
        ErrorAction = 'Stop'
    }

    $bodyJson = $null
    if ($Body) {
        $bodyJson = ($Body | ConvertTo-Json -Depth 10)
        $params['Body'] = $bodyJson
        Write-Action1Log "Request body (raw JSON)" -Level TRACE
        Write-Action1Log $bodyJson -Level TRACE
        Write-Action1Log "Request body (parsed)" -Level TRACE -Data $Body
    } else {
        Write-Action1Log "Request body: (none)" -Level TRACE
    }

    # TRACE: Log complete request summary
    Write-Action1Log "--- REQUEST SUMMARY ---" -Level TRACE
    Write-Action1Log "$Method $uri" -Level TRACE
    Write-Action1Log "Content-Type: application/json" -Level TRACE
    Write-Action1Log "Body size: $(if ($bodyJson) { $bodyJson.Length } else { 0 }) bytes" -Level TRACE
    Write-Action1Log "-----------------------" -Level TRACE

    $maxRetries = 3
    $retryCount = 0
    $baseDelay = 1  # seconds

    while ($true) {
        try {
            Write-Action1Log "Executing API request..." -Level INFO
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            # Use Invoke-WebRequest for full HTTP details at TRACE level
            $webResponse = Invoke-WebRequest @params

            $stopwatch.Stop()
            $statusCode = $webResponse.StatusCode
            $statusDescription = $webResponse.StatusDescription

            Write-Action1Log "API request completed: HTTP $statusCode in $($stopwatch.ElapsedMilliseconds)ms" -Level INFO

            # TRACE: Log complete response details
            Write-Action1Log "========== RESPONSE ==========" -Level TRACE
            Write-Action1Log "HTTP Status: $statusCode $statusDescription" -Level TRACE
            Write-Action1Log "Duration: $($stopwatch.ElapsedMilliseconds)ms" -Level TRACE

            # Log all response headers
            Write-Action1Log "Response Headers:" -Level TRACE
            foreach ($headerName in $webResponse.Headers.Keys) {
                $headerValue = $webResponse.Headers[$headerName]
                if ($headerValue -is [array]) { $headerValue = $headerValue -join ', ' }
                Write-Action1Log "  $headerName`: $headerValue" -Level TRACE
            }

            # Log content details
            $contentLength = if ($webResponse.Headers['Content-Length']) { $webResponse.Headers['Content-Length'] } else { $webResponse.Content.Length }
            $contentType = if ($webResponse.Headers['Content-Type']) { $webResponse.Headers['Content-Type'] } else { 'unknown' }
            Write-Action1Log "Content-Type: $contentType" -Level TRACE
            Write-Action1Log "Content-Length: $contentLength bytes" -Level TRACE

            # Log raw response body
            Write-Action1Log "Response Body (raw):" -Level TRACE
            Write-Action1Log $webResponse.Content -Level TRACE
            Write-Action1Log "================================" -Level TRACE

            # Parse JSON response
            $response = $webResponse.Content | ConvertFrom-Json

            # Also log parsed data
            Write-Action1Log "Response data (parsed)" -Level TRACE -Data $response

            return $response
        }
        catch {
            $stopwatch.Stop()
            $retryCount++

            # Determine HTTP status code from the exception
            $errorStatusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }

            # Check if this is a retryable error (429 rate limit, 5xx server errors, or network failures)
            $isRetryable = $errorStatusCode -in @(429, 500, 502, 503, 504) -or
                           $_.Exception -is [System.Net.Http.HttpRequestException] -or
                           ($_.Exception.InnerException -and $_.Exception.InnerException -is [System.Net.Sockets.SocketException])

            if ($isRetryable -and $retryCount -le $maxRetries) {
                # Calculate delay: use Retry-After header for 429, otherwise exponential backoff
                $delay = $baseDelay * [Math]::Pow(2, $retryCount - 1)
                if ($errorStatusCode -eq 429 -and $_.Exception.Response.Headers) {
                    try {
                        $retryAfterValues = $_.Exception.Response.Headers.GetValues('Retry-After')
                        if ($retryAfterValues) {
                            $retryAfterSec = [int]$retryAfterValues[0]
                            $delay = [Math]::Max($delay, $retryAfterSec)
                        }
                    } catch {
                        # Retry-After header not present or not parseable, use backoff
                    }
                }

                Write-Action1Log "Request failed (HTTP $errorStatusCode), retrying in ${delay}s ($retryCount/$maxRetries)..." -Level WARN
                Start-Sleep -Seconds $delay
                continue
            }

            # Non-retryable error or max retries exceeded — log fully and throw
            Write-Action1Log "API request failed after $($stopwatch.ElapsedMilliseconds)ms" -Level ERROR -ErrorRecord $_

            # Try to extract more details from the exception
            if ($_.Exception.Response) {
                $errorResponse = $_.Exception.Response
                Write-Action1Log "========== ERROR RESPONSE ==========" -Level TRACE
                Write-Action1Log "HTTP Status: $([int]$errorResponse.StatusCode) $($errorResponse.StatusCode)" -Level TRACE
                Write-Action1Log "Status Description: $($errorResponse.ReasonPhrase)" -Level TRACE

                # Try to read error response body
                try {
                    # HttpResponseMessage uses Content.ReadAsStringAsync()
                    if ($errorResponse.Content) {
                        $errorBody = $errorResponse.Content.ReadAsStringAsync().Result
                        Write-Action1Log "Error Response Body:" -Level TRACE
                        Write-Action1Log $errorBody -Level TRACE
                    }
                }
                catch {
                    Write-Action1Log "Could not read error response body: $_" -Level TRACE
                }
                Write-Action1Log "=====================================" -Level TRACE
            }

            # Also check ErrorDetails which PowerShell often populates
            if ($_.ErrorDetails.Message) {
                Write-Action1Log "ErrorDetails.Message:" -Level TRACE
                Write-Action1Log $_.ErrorDetails.Message -Level TRACE
            }

            if ($_.ErrorDetails.Message) {
                Write-Action1Log "Error details from API" -Level ERROR -Data ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue)
            }

            if ($retryCount -gt $maxRetries) {
                Write-Action1Log "Max retries ($maxRetries) exceeded for $Method $uri" -Level ERROR
            }

            throw
        }
    }
}
