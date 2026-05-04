function Set-Action1ApiCredentials {
    <#
    .SYNOPSIS
        Sets the Action1 API credentials for use in the module.

    .DESCRIPTION
        Configures the Client ID, Client Secret, and Region for authenticating with Action1 API.
        Credentials are stored in memory for the current session only.
        If Region is not specified, prompts the user to select one.

    .PARAMETER ClientId
        The Action1 API Client ID.

    .PARAMETER ClientSecret
        The Action1 API Client Secret.

    .PARAMETER Region
        The Action1 region (NorthAmerica, Europe, Australia).
        If not specified, prompts the user to select.

    .PARAMETER SaveToProfile
        If specified, saves credentials to a secure local file for persistence.

    .EXAMPLE
        Set-Action1ApiCredentials -ClientId "your-client-id" -ClientSecret "your-secret" -Region "Australia"

    .EXAMPLE
        Set-Action1ApiCredentials -ClientId "your-client-id" -ClientSecret "your-secret"
        # Will prompt for region selection
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [string]$ClientSecret,

        [Parameter()]
        [ValidateSet('NorthAmerica', 'Europe', 'Australia')]
        [string]$Region,

        [Parameter()]
        [switch]$SaveToProfile
    )

    Write-Action1Log "Configuring Action1 API credentials" -Level INFO
    Write-Action1Log "Client ID length: $($ClientId.Length) characters" -Level DEBUG

    # Prompt for region if not provided
    if (-not $Region) {
        Write-Host "`nSelect Action1 Region:" -ForegroundColor Cyan
        Write-Host "  [0] NorthAmerica (app.action1.com) (default)"
        Write-Host "  [1] Europe (app.eu.action1.com)"
        Write-Host "  [2] Australia (app.au.action1.com)"

        $selection = Read-Host "`nEnter selection (0-2)"
        $Region = switch ($selection) {
            '0' { 'NorthAmerica' }
            '' { 'NorthAmerica' }
            '1' { 'Europe' }
            '2' { 'Australia' }
            default {
                Write-Warning "Invalid selection. Defaulting to NorthAmerica."
                'NorthAmerica'
            }
        }
        Write-Host "Selected: $Region" -ForegroundColor Green
    }

    Write-Action1Log "Selected region: $Region" -Level INFO

    $script:Action1ClientId = $ClientId
    $script:Action1ClientSecret = $ClientSecret
    $script:Action1Region = $Region
    $script:Action1BaseUri = $script:Action1RegionUrls[$Region]

    Write-Action1Log "API Base URI set to: $($script:Action1BaseUri)" -Level DEBUG
    Write-Action1Log "Credentials set in memory for current session" -Level INFO

    if ($SaveToProfile) {
        Write-Action1Log "Saving credentials to profile" -Level INFO

        Write-Action1Log "Profile path: $script:Action1ConfigDir" -Level DEBUG

        if (-not (Test-Path $script:Action1ConfigDir)) {
            Write-Action1Log "Creating profile directory" -Level DEBUG
            New-Item -Path $script:Action1ConfigDir -ItemType Directory -Force | Out-Null
        }

        try {
            if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
                # Windows: Use DPAPI encryption via Export-Clixml (per-user encrypted)
                $credFile = Join-Path $script:Action1ConfigDir "credentials.xml"
                @{
                    ClientId     = $ClientId
                    ClientSecret = $ClientSecret | ConvertTo-SecureString -AsPlainText -Force
                    Region       = $Region
                } | Export-Clixml -Path $credFile -Force

                # Remove legacy plaintext file if it exists
                $legacyFile = Join-Path $script:Action1ConfigDir "credentials.json"
                if (Test-Path $legacyFile) {
                    Remove-Item $legacyFile -Force
                    Write-Action1Log "Removed legacy plaintext credentials file" -Level INFO
                }
            }
            else {
                # macOS/Linux: No DPAPI available, use JSON with restrictive file permissions
                $credFile = Join-Path $script:Action1ConfigDir "credentials.json"
                @{
                    ClientId     = $ClientId
                    ClientSecret = $ClientSecret
                    Region       = $Region
                } | ConvertTo-Json | Set-Content $credFile -Force
                # Set file permissions to owner-only (chmod 600)
                & chmod 600 $credFile
            }

            Write-Action1Log "Credentials saved to: $credFile" -Level INFO
            Write-Host "Credentials saved to: $credFile" -ForegroundColor Green
        }
        catch {
            Write-Action1Log "Failed to save credentials to file" -Level ERROR -ErrorRecord $_
            throw
        }
    }

    Write-Host "`nAction1 API credentials configured successfully." -ForegroundColor Green
    Write-Host "Region: $Region" -ForegroundColor Cyan
    Write-Host "API Endpoint: $($script:Action1BaseUri)" -ForegroundColor Cyan
}
