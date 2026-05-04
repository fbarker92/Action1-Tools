function Write-ManifestFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Manifest,
        
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    Write-Action1Log "Writing manifest to: $Path" -Level DEBUG
    Write-Action1Log "Manifest data to write" -Level TRACE -Data $Manifest
    
    try {
        $Manifest | ConvertTo-Json -Depth 10 | Set-Content $Path -Force
        Write-Action1Log "Manifest saved successfully" -Level INFO
    }
    catch {
        Write-Action1Log "Failed to save manifest file" -Level ERROR -ErrorRecord $_
        throw "Failed to save manifest file: $($_.Exception.Message)"
    }
}
