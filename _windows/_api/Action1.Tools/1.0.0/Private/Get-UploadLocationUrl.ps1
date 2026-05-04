function Get-UploadLocationUrl {
    <#
    .SYNOPSIS
        Normalizes the upload location URL returned by the Action1 API.

    .DESCRIPTION
        The X-Upload-Location header may return a relative path (e.g., /API/...)
        or a full URL. This function normalizes it to a full URL.

    .PARAMETER BaseUri
        The base API URI (e.g., https://app.eu.action1.com/api/3.0)

    .PARAMETER Location
        The location value from the X-Upload-Location header.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaseUri,

        [Parameter(Mandatory)]
        [string]$Location
    )

    # If already a full URL, return as-is
    if ($Location -match '^https?://') {
        return $Location
    }

    # Extract origin from base URI
    $uri = [System.Uri]$BaseUri
    $origin = "$($uri.Scheme)://$($uri.Host)"
    if ($uri.Port -ne 80 -and $uri.Port -ne 443) {
        $origin = "$($origin):$($uri.Port)"
    }

    # Handle /API/* paths (convert to /api/3.0/*)
    if ($Location -match '^/API/') {
        $Location = $Location -replace '^/API/', '/api/3.0/'
    }

    # Build full URL
    if ($Location -match '^/') {
        return "$origin$Location"
    }
    else {
        return "$origin/$Location"
    }
}
