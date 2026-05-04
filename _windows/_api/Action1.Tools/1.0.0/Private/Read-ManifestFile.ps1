function Read-ManifestFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    Write-Action1Log "Reading manifest file: $Path" -Level DEBUG
    
    if (-not (Test-Path $Path)) {
        Write-Action1Log "Manifest file not found: $Path" -Level ERROR
        throw "Manifest file not found: $Path"
    }
    
    try {
        $manifest = Get-Content $Path -Raw | ConvertFrom-Json
        Write-Action1Log "Manifest loaded successfully" -Level INFO
        Write-Action1Log "Manifest contents" -Level TRACE -Data $manifest
        return $manifest
    }
    catch {
        Write-Action1Log "Failed to parse manifest file" -Level ERROR -ErrorRecord $_
        throw "Failed to parse manifest file: $($_.Exception.Message)"
    }
}
