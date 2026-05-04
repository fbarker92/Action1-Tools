function Get-Action1ApiCredentials {
    <#
    .SYNOPSIS
        Retrieves the current Action1 API credentials and validates permissions.

    .DESCRIPTION
        Returns information about the currently configured API credentials including
        region, endpoint, and token status. Optionally validates the credentials
        by making an API call to check accessible organizations and permissions.

    .PARAMETER TestConnection
        If specified, makes an API call to validate credentials and check permissions.

    .PARAMETER ShowSecret
        If specified, includes the client secret in the output (masked by default).

    .EXAMPLE
        Get-Action1ApiCredentials
        # Returns current credential info without API validation

    .EXAMPLE
        Get-Action1ApiCredentials -TestConnection
        # Returns credential info and validates by checking accessible organizations

    .EXAMPLE
        Get-Action1ApiCredentials -ShowSecret
        # Includes the client secret in the output
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$TestConnection,

        [Parameter()]
        [switch]$ShowSecret
    )

    Write-Action1Log "Retrieving Action1 API credentials" -Level INFO

    # Check if credentials are configured
    $isConfigured = $null -ne $script:Action1ClientId -and $null -ne $script:Action1ClientSecret

    if (-not $isConfigured) {
        Write-Action1Log "No credentials configured" -Level WARN
        Write-Host "No Action1 API credentials configured." -ForegroundColor Yellow
        Write-Host "Use Set-Action1ApiCredentials to configure." -ForegroundColor Cyan
        return [PSCustomObject]@{
            Configured     = $false
            ClientId       = $null
            Region         = $null
            Endpoint       = $null
            TokenStatus    = 'Not Available'
            Organizations  = @()
            Permissions    = @()
        }
    }

    # Build credential info object
    $credInfo = [PSCustomObject]@{
        Configured     = $true
        ClientId       = $script:Action1ClientId
        ClientSecret   = if ($ShowSecret) { $script:Action1ClientSecret } else { '********' }
        Region         = $script:Action1Region
        Endpoint       = $script:Action1BaseUri
        TokenStatus    = 'Unknown'
        TokenExpiry    = $null
        Organizations  = @()
        Permissions    = @()
    }

    # Check token status
    if ($script:Action1AccessToken) {
        if ($script:Action1TokenExpiry -and (Get-Date) -lt $script:Action1TokenExpiry) {
            $credInfo.TokenStatus = 'Valid'
            $credInfo.TokenExpiry = $script:Action1TokenExpiry
        }
        else {
            $credInfo.TokenStatus = 'Expired'
            $credInfo.TokenExpiry = $script:Action1TokenExpiry
        }
    }
    else {
        $credInfo.TokenStatus = 'Not Acquired'
    }

    Write-Action1Log "Credentials configured for region: $($script:Action1Region)" -Level DEBUG

    # If TestConnection requested, validate by calling API
    if ($TestConnection) {
        Write-Action1Log "Testing connection and checking permissions..." -Level INFO
        Write-Host "`nValidating credentials..." -ForegroundColor Cyan

        try {
            # Get organizations to validate credentials and check access
            $orgsResponse = Invoke-Action1ApiRequest -Endpoint "organizations" -Method GET
            $orgs = if ($orgsResponse.items) { @($orgsResponse.items) } else { @($orgsResponse) }

            $credInfo.Organizations = $orgs | ForEach-Object {
                [PSCustomObject]@{
                    Id   = $_.id
                    Name = $_.name
                    Type = $_.type
                }
            }

            # Update token status after successful call
            $credInfo.TokenStatus = 'Valid'
            $credInfo.TokenExpiry = $script:Action1TokenExpiry

            # Determine permissions based on accessible resources
            $permissions = @()

            # Check organizations access
            if ($orgs.Count -gt 0) {
                $permissions += 'Organizations:Read'
            }

            # Try to check software repository access (use first org or 'all')
            $testOrgId = if ($orgs.Count -gt 0) { $orgs[0].id } else { 'all' }
            try {
                $null = Invoke-Action1ApiRequest `
                    -Endpoint "software-repository/$testOrgId`?limit=1" `
                    -Method GET
                $permissions += 'SoftwareRepository:Read'
                Write-Action1Log "Software repository access confirmed" -Level DEBUG
            }
            catch {
                Write-Action1Log "No software repository read access" -Level DEBUG
            }

            # Try to check automations access
            try {
                $null = Invoke-Action1ApiRequest `
                    -Endpoint "policies/schedules/$testOrgId`?limit=1" `
                    -Method GET
                $permissions += 'Automations:Read'
                Write-Action1Log "Automations access confirmed" -Level DEBUG
            }
            catch {
                Write-Action1Log "No automations read access" -Level DEBUG
            }

            # Try to check endpoint groups access
            try {
                $null = Invoke-Action1ApiRequest `
                    -Endpoint "endpoints/groups/$testOrgId`?limit=1" `
                    -Method GET
                $permissions += 'EndpointGroups:Read'
                Write-Action1Log "Endpoint groups access confirmed" -Level DEBUG
            }
            catch {
                Write-Action1Log "No endpoint groups read access" -Level DEBUG
            }

            $credInfo.Permissions = $permissions

            Write-Host "`n✓ Credentials validated successfully" -ForegroundColor Green
            Write-Host "`nAccessible Organizations:" -ForegroundColor Cyan
            foreach ($org in $credInfo.Organizations) {
                Write-Host "  - $($org.Name) ($($org.Id))" -ForegroundColor White
            }

            Write-Host "`nDetected Permissions:" -ForegroundColor Cyan
            foreach ($perm in $permissions) {
                Write-Host "  ✓ $perm" -ForegroundColor Green
            }
        }
        catch {
            Write-Action1Log "Failed to validate credentials" -Level ERROR -ErrorRecord $_
            Write-Host "`n✗ Failed to validate credentials: $($_.Exception.Message)" -ForegroundColor Red
            $credInfo.TokenStatus = 'Invalid'
        }
    }
    else {
        # Display basic info without API call
        Write-Host "`nAction1 API Credentials:" -ForegroundColor Cyan
        Write-Host "  Client ID:  $($credInfo.ClientId)" -ForegroundColor White
        Write-Host "  Region:     $($credInfo.Region)" -ForegroundColor White
        Write-Host "  Endpoint:   $($credInfo.Endpoint)" -ForegroundColor White
        Write-Host "  Token:      $($credInfo.TokenStatus)" -ForegroundColor $(if ($credInfo.TokenStatus -eq 'Valid') { 'Green' } elseif ($credInfo.TokenStatus -eq 'Expired') { 'Yellow' } else { 'Gray' })
        if ($credInfo.TokenExpiry) {
            Write-Host "  Expires:    $($credInfo.TokenExpiry)" -ForegroundColor Gray
        }
        Write-Host "`nUse -TestConnection to validate credentials and check permissions." -ForegroundColor DarkGray
    }

    return $credInfo
}
