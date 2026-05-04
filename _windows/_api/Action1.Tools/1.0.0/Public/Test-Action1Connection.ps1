function Test-Action1Connection {
    <#
    .SYNOPSIS
        Tests the connection to Action1 API.
    
    .DESCRIPTION
        Validates that the API credentials are correct and the API is accessible.
    
    .EXAMPLE
        Test-Action1Connection
    #>
    [CmdletBinding()]
    param()
    
    Write-Action1Log "Testing Action1 API connection" -Level INFO
    
    try {
        Write-Action1Log "Attempting to query organizations endpoint" -Level DEBUG
        # Try to list organizations (lightweight API call)
        $response = Invoke-Action1ApiRequest -Endpoint "organizations" -Method GET
        
        Write-Action1Log "API connection test successful" -Level INFO
        Write-Action1Log "Organizations retrieved" -Level TRACE -Data $response
        
        Write-Host "✓ Successfully connected to Action1 API" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Action1Log "API connection test failed" -Level ERROR -ErrorRecord $_
        Write-Host "✗ Failed to connect to Action1 API" -ForegroundColor Red
        return $false
    }
}
