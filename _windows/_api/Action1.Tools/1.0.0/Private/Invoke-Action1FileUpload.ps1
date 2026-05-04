function Invoke-Action1FileUpload {
    <#
    .SYNOPSIS
        Uploads a file with progress tracking and chunking support.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [string]$Endpoint,
        
        [Parameter()]
        [int]$ChunkSizeMB = 32,
        
        [Parameter()]
        [hashtable]$AdditionalData
    )
    
    Write-Action1Log "Starting file upload: $FilePath" -Level INFO
    
    if (-not (Test-Path $FilePath)) {
        throw "File not found: $FilePath"
    }
    
    $fileInfo = Get-Item $FilePath
    $fileSize = $fileInfo.Length
    $fileName = $fileInfo.Name
    
    Write-Action1Log "File size: $(ConvertTo-FileSize -Bytes $fileSize)" -Level DEBUG
    
    # For small files (< 32MB), upload directly
    if ($fileSize -lt (32 * 1024 * 1024)) {
        Write-Action1Log "File is small, uploading directly without chunking" -Level DEBUG
        return Invoke-Action1DirectUpload -FilePath $FilePath -Endpoint $Endpoint -AdditionalData $AdditionalData
    }
    
    # For large files, use chunked upload
    Write-Action1Log "File is large, using chunked upload" -Level DEBUG
    return Invoke-Action1ChunkedUpload -FilePath $FilePath -Endpoint $Endpoint -ChunkSizeMB $ChunkSizeMB -AdditionalData $AdditionalData
}
