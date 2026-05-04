function Get-Action1Headers {
    [CmdletBinding()]
    param()

    Write-Action1Log "Generating authentication headers" -Level TRACE

    # Get or refresh the access token
    $token = Get-Action1AccessToken

    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }

    # TRACE logging for headers (mask sensitive data)
    Write-Action1Log "Request headers" -Level TRACE -Data @{
        'Authorization' = "Bearer ***MASKED*** (length: $($token.Length))"
        'Content-Type'  = $headers['Content-Type']
        'Accept'        = $headers['Accept']
    }

    Write-Action1Log "Authentication headers generated successfully" -Level DEBUG

    return $headers
}
