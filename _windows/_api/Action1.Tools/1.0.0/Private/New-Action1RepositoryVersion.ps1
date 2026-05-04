function New-Action1RepositoryVersion {
    <#
    .SYNOPSIS
        Creates a new version in a software repository.

    .DESCRIPTION
        Creates a new version with the specified properties, suitable for uploading
        an installer file.

    .PARAMETER OrganizationId
        The organization ID (or "all" for enterprise-wide).

    .PARAMETER RepositoryId
        The software repository ID.

    .PARAMETER Version
        The version number string.

    .PARAMETER AppNameMatch
        Application name matching pattern for detection.

    .PARAMETER FileName
        The installer file name.

    .PARAMETER Platform
        The upload platform: Windows_64, Windows_32, Windows_ARM64, Mac_AppleSilicon, Mac_IntelCPU.

    .PARAMETER InstallType
        Installation type: msi, exe, msix, or script.

    .PARAMETER ReleaseDate
        Release date (defaults to today).

    .PARAMETER OS
        Array of supported OS versions.

    .PARAMETER SuccessExitCodes
        Comma-separated success exit codes (default "0").

    .PARAMETER RebootExitCodes
        Comma-separated reboot exit codes (default "1641,3010").

    .OUTPUTS
        Returns the created version object with its ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationId,

        [Parameter(Mandatory)]
        [string]$RepositoryId,

        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string]$AppNameMatch,

        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter(Mandatory)]
        [ValidateSet('Windows_64', 'Windows_32', 'Windows_ARM64', 'Mac_AppleSilicon', 'Mac_IntelCPU')]
        [string]$Platform,

        [Parameter()]
        [ValidateSet('msi', 'exe', 'msix', 'script')]
        [string]$InstallType = 'msi',

        [Parameter()]
        [string]$ReleaseDate = (Get-Date -Format 'yyyy-MM-dd'),

        [Parameter()]
        [string[]]$OS = @('Windows 11', 'Windows 10', 'Windows'),

        [Parameter()]
        [string]$SuccessExitCodes = "0",

        [Parameter()]
        [string]$RebootExitCodes = "1641,3010",

        [Parameter()]
        [string]$Notes = "",

        [Parameter()]
        [ValidateSet('Regular Updates', 'Security Updates', 'Critical Updates')]
        [string]$UpdateType = 'Regular Updates',

        [Parameter()]
        [ValidateSet('Unspecified', 'Low', 'Medium', 'High', 'Critical')]
        [string]$SecuritySeverity = 'Unspecified',

        [Parameter()]
        [ValidateSet('Published', 'Draft')]
        [string]$Status = 'Published',

        [Parameter()]
        [ValidateSet('New', 'Approved', 'Declined')]
        [string]$ApprovalStatus = 'Approved',

        [Parameter()]
        [ValidateSet('yes', 'no')]
        [string]$EulaAccepted = 'no',

        [Parameter()]
        [hashtable]$AllPlatformFiles = @{},

        [Parameter()]
        [string]$SecurityCVE = ""
    )

    Write-Action1Log "Creating version $Version for repository $RepositoryId..." -Level INFO

    $token = Get-Action1AccessToken
    $uri = "$script:Action1BaseUri/software-repository/$OrganizationId/$RepositoryId/versions"

    # Build the file_name object with all platform-specific entries
    $fileNameObj = @{}

    # Add files from AllPlatformFiles hashtable if provided
    if ($AllPlatformFiles.Count -gt 0) {
        foreach ($plat in $AllPlatformFiles.Keys) {
            $fileNameObj[$plat] = @{
                name = $AllPlatformFiles[$plat]
                type = "cloud"
            }
        }
    }
    else {
        # Fallback to single platform/filename
        $fileNameObj[$Platform] = @{
            name = $FileName
            type = "cloud"
        }
    }

    $body = @{
        version             = $Version
        app_name_match      = $AppNameMatch
        release_date        = $ReleaseDate
        os                  = $OS
        install_type        = $InstallType
        success_exit_codes  = $SuccessExitCodes
        reboot_exit_codes   = $RebootExitCodes
        notes               = $Notes
        update_type         = $UpdateType
        security_severity   = $SecuritySeverity
        status              = $Status
        approval_status     = $ApprovalStatus
        EULA_accepted       = $EulaAccepted
        security_CVE        = $SecurityCVE
        file_name           = $fileNameObj
    } | ConvertTo-Json -Depth 5

    Write-Action1Log "Version payload: $body" -Level DEBUG

    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }

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
            throw "Version creation returned no ID"
        }

        Write-Action1Log "Created version: $Version (ID: $($response.id))" -Level INFO
        return $response
    }
    catch {
        # Try to extract error details from the response
        $errorMessage = $_.Exception.Message
        if ($_.ErrorDetails.Message) {
            try {
                $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
                $errorMessage = "$errorMessage - API Error: $($errorBody | ConvertTo-Json -Compress)"
            }
            catch {
                $errorMessage = "$errorMessage - Response: $($_.ErrorDetails.Message)"
            }
        }
        Write-Action1Log "Failed to create version: $errorMessage" -Level ERROR
        Write-Action1Log "Request URI: $uri" -Level DEBUG
        Write-Action1Log "Request Body: $body" -Level DEBUG
        throw $errorMessage
    }
}
