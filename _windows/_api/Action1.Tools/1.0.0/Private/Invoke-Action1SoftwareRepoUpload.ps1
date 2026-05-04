function Invoke-Action1SoftwareRepoUpload {
    <#
    .SYNOPSIS
        Uploads a file to Action1 software repository using resumable upload protocol.

    .DESCRIPTION
        Implements the Action1 resumable upload protocol:
        1. Initializes upload session (POST with X-Upload-Content-* headers)
        2. Uploads file in chunks using Content-Range headers
        3. Each chunk expects HTTP 308 (continue) or 200/201/204 (complete)

        This is the correct upload method for Action1 software repository,
        matching the protocol used by the official zsh deployment script.

    .PARAMETER FilePath
        Path to the file to upload.

    .PARAMETER OrganizationId
        The organization ID (or "all" for enterprise-wide).

    .PARAMETER PackageId
        The software repository package ID.

    .PARAMETER VersionId
        The version ID to upload to.

    .PARAMETER Platform
        The platform identifier. Valid values:
        - Windows_64, Windows_32, Windows_ARM64
        - Mac_AppleSilicon, Mac_IntelCPU

    .PARAMETER ChunkSizeMB
        Size of each upload chunk in megabytes. Default is 24MB.
        Minimum is 5MB.

    .PARAMETER ProgressId
        The progress bar ID for this upload. Default is 1.
        Use different IDs for parallel uploads.

    .PARAMETER ProgressState
        A synchronized hashtable for sharing progress state across parallel uploads.
        Used by Invoke-Action1MultiFileUpload.

    .PARAMETER ShowProgress
        Whether to show progress bars. Default is true.

    .EXAMPLE
        Invoke-Action1SoftwareRepoUpload -FilePath "C:\installer.msi" `
            -OrganizationId "all" -PackageId "pkg123" -VersionId "ver456" `
            -Platform "Windows_64"

    .EXAMPLE
        # Upload a Mac installer
        Invoke-Action1SoftwareRepoUpload -FilePath "/path/to/app.zip" `
            -OrganizationId "org789" -PackageId "pkg123" -VersionId "ver456" `
            -Platform "Mac_AppleSilicon" -ChunkSizeMB 32
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$OrganizationId,

        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
        [string]$VersionId,

        [Parameter(Mandatory)]
        [ValidateSet('Windows_64', 'Windows_32', 'Windows_ARM64', 'Mac_AppleSilicon', 'Mac_IntelCPU')]
        [string]$Platform,

        [Parameter()]
        [ValidateRange(5, 100)]
        [int]$ChunkSizeMB = 24,

        [Parameter()]
        [int]$ProgressId = 1,

        [Parameter()]
        [hashtable]$ProgressState,

        [Parameter()]
        [bool]$ShowProgress = $true,

        [Parameter()]
        [hashtable]$OverallContext
    )

    # Validate file exists
    if (-not (Test-Path $FilePath)) {
        throw "File not found: $FilePath"
    }

    $fileInfo = Get-Item $FilePath
    $fileSize = $fileInfo.Length
    $fileName = $fileInfo.Name
    $chunkSize = $ChunkSizeMB * 1024 * 1024
    $totalChunks = [Math]::Ceiling($fileSize / $chunkSize)

    # Platform display name for progress
    $platformDisplay = switch ($Platform) {
        'Windows_64' { 'x64' }
        'Windows_32' { 'x86' }
        'Windows_ARM64' { 'ARM64' }
        'Mac_AppleSilicon' { 'Apple Silicon' }
        'Mac_IntelCPU' { 'Intel' }
        default { $Platform }
    }

    Write-Action1Log "Starting software repository upload" -Level INFO
    Write-Action1Log "File: $fileName, Size: $(ConvertTo-FileSize -Bytes $fileSize), Chunks: $totalChunks x ${ChunkSizeMB}MB" -Level INFO

    # Initialize progress state if provided
    if ($ProgressState) {
        $ProgressState[$Platform] = @{
            FileName = $fileName
            FileSize = $fileSize
            BytesUploaded = 0
            ChunkNumber = 0
            TotalChunks = $totalChunks
            Status = 'Initializing'
            Speed = 0
            StartTime = Get-Date
        }
    }

    try {
        # Step 1: Initialize upload session
        if ($ShowProgress) {
            Write-Action1Progress -Activity "[$platformDisplay] $fileName" -Status "Initializing upload..." -PercentComplete 0 -Id $ProgressId
        }

        $uploadUrl = Initialize-Action1SoftwareRepoUpload `
            -OrganizationId $OrganizationId `
            -PackageId $PackageId `
            -VersionId $VersionId `
            -Platform $Platform `
            -FileSize $fileSize

        Write-Action1Log "Upload session initialized, URL: $uploadUrl" -Level DEBUG

        # Step 2: Upload file in chunks
        $token = Get-Action1AccessToken
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        $buffer = New-Object byte[] $chunkSize
        $offset = 0
        $chunkNumber = 0
        $uploadComplete = $false
        $uploadStartTime = Get-Date

        try {
            while ($offset -lt $fileSize) {
                $chunkNumber++
                $bytesToRead = [Math]::Min($chunkSize, $fileSize - $offset)
                $bytesRead = $fileStream.Read($buffer, 0, $bytesToRead)

                $startByte = $offset
                $endByte = $offset + $bytesRead - 1
                $contentRange = "bytes $startByte-$endByte/$fileSize"

                # Calculate progress and speed
                $percentComplete = [int](($offset / $fileSize) * 100)
                $uploadedSize = ConvertTo-FileSize -Bytes $offset
                $totalSize = ConvertTo-FileSize -Bytes $fileSize
                $elapsed = (Get-Date) - $uploadStartTime
                $speed = if ($elapsed.TotalSeconds -gt 0) { $offset / $elapsed.TotalSeconds } else { 0 }
                $speedDisplay = ConvertTo-FileSize -Bytes $speed
                $remaining = if ($speed -gt 0) { ($fileSize - $offset) / $speed } else { 0 }
                $remainingDisplay = if ($remaining -gt 60) { "{0:N0}m {1:N0}s" -f [Math]::Floor($remaining / 60), ($remaining % 60) } else { "{0:N0}s" -f $remaining }

                # Update progress state if provided
                if ($ProgressState) {
                    $ProgressState[$Platform].BytesUploaded = $offset
                    $ProgressState[$Platform].ChunkNumber = $chunkNumber
                    $ProgressState[$Platform].Status = 'Uploading'
                    $ProgressState[$Platform].Speed = $speed
                }

                if ($ShowProgress) {
                    Write-Action1Progress `
                        -Activity "[$platformDisplay] $fileName" `
                        -Status "Chunk $chunkNumber/$totalChunks | $uploadedSize / $totalSize | $speedDisplay/s | ETA: $remainingDisplay" `
                        -PercentComplete $percentComplete `
                        -Id $ProgressId
                }

                Write-Action1Log "Uploading chunk $($chunkNumber)/$($totalChunks): $contentRange (chunk bytes: $bytesRead, total file: $fileSize)" -Level DEBUG

                # Prepare the chunk data
                $chunkData = New-Object byte[] $bytesRead
                [Array]::Copy($buffer, 0, $chunkData, 0, $bytesRead)

                $chunkHeaders = @{
                    'Authorization'  = "Bearer $token"
                    'Content-Type'   = 'application/octet-stream'
                    'Content-Range'  = $contentRange
                }

                # TRACE: Log full chunk request details
                Write-Action1Log "========== CHUNK $chunkNumber REQUEST ==========" -Level TRACE
                Write-Action1Log "PUT $uploadUrl" -Level TRACE
                Write-Action1Log "Request Headers:" -Level TRACE
                Write-Action1Log "  Authorization: Bearer ***MASKED***" -Level TRACE
                Write-Action1Log "  Content-Type: $($chunkHeaders['Content-Type'])" -Level TRACE
                Write-Action1Log "  Content-Range: $($chunkHeaders['Content-Range'])" -Level TRACE
                Write-Action1Log "Request Body: <binary data, $bytesRead bytes>" -Level TRACE
                Write-Action1Log "===============================================" -Level TRACE

                # Upload chunk with real-time progress
                $progressParams = @{
                    Activity = "[$platformDisplay] $fileName"
                    Id = $ProgressId
                    FileOffset = $offset
                    FileSize = $fileSize
                    ChunkNumber = $chunkNumber
                    TotalChunks = $totalChunks
                    UploadStartTime = $uploadStartTime
                    OverallContext = $OverallContext
                }

                $response = Send-ChunkWithProgress `
                    -Uri $uploadUrl `
                    -Headers $chunkHeaders `
                    -Data $chunkData `
                    -ProgressParams $progressParams `
                    -ShowProgress $ShowProgress

                $statusCode = $response.StatusCode
                $statusDescription = $response.StatusDescription

                # TRACE: Log full chunk response details
                Write-Action1Log "========== CHUNK $chunkNumber RESPONSE ==========" -Level TRACE
                Write-Action1Log "HTTP Status: $statusCode $statusDescription" -Level TRACE
                Write-Action1Log "Duration: $($response.ElapsedMilliseconds)ms" -Level TRACE
                Write-Action1Log "Response Headers:" -Level TRACE
                foreach ($headerName in $response.Headers.Keys) {
                    $headerValue = $response.Headers[$headerName]
                    Write-Action1Log "  $headerName`: $headerValue" -Level TRACE
                }
                $respContentType = if ($response.Headers['Content-Type']) { $response.Headers['Content-Type'] } else { 'none' }
                Write-Action1Log "Content-Type: $respContentType" -Level TRACE
                if ($response.Content -and $response.Content.Length -gt 0) {
                    Write-Action1Log "Response Body:" -Level TRACE
                    Write-Action1Log $response.Content -Level TRACE
                }
                Write-Action1Log "================================================" -Level TRACE

                # Log response details for debugging
                $rangeHeader = $response.Headers['Range']
                Write-Action1Log "Chunk $chunkNumber response: Status=$statusCode, Range=$rangeHeader" -Level DEBUG

                # Check response status
                if ($statusCode -eq 308) {
                    # Continue uploading - 308 means server received data but expects more
                    Write-Action1Log "Chunk $chunkNumber uploaded successfully (308 - continue)" -Level DEBUG
                }
                elseif ($statusCode -in @(200, 201, 204)) {
                    # Upload complete
                    Write-Action1Log "Chunk $chunkNumber uploaded - upload complete ($statusCode)" -Level INFO
                    $uploadComplete = $true
                    break
                }
                else {
                    $errorContent = $response.Content
                    Write-Action1Log "Chunk upload failed with status $statusCode`: $errorContent" -Level ERROR
                    throw "Chunk upload failed with status code: $statusCode"
                }

                $offset += $bytesRead
            }
        }
        finally {
            $fileStream.Close()
            $fileStream.Dispose()
        }

        # Update final progress state
        if ($ProgressState) {
            $ProgressState[$Platform].BytesUploaded = $fileSize
            $ProgressState[$Platform].Status = if ($uploadComplete) { 'Complete' } else { 'Warning' }
        }

        # Check if upload actually completed
        if (-not $uploadComplete) {
            Write-Action1Log "WARNING: All chunks uploaded but server did not confirm completion (expected 200, got 308 on all chunks)" -Level WARN
            Write-Host "⚠ Upload may be incomplete: $fileName - server did not confirm completion" -ForegroundColor Yellow
        }

        if ($ShowProgress) {
            Write-Action1Progress -Activity "[$platformDisplay] $fileName" -Status "Complete" -PercentComplete 100 -Id $ProgressId
            Start-Sleep -Milliseconds 300
            Write-Progress -Activity "[$platformDisplay] $fileName" -Id $ProgressId -Completed
        }

        Write-Action1Log "Software repository upload completed successfully" -Level INFO

        return @{
            Success = $true
            FileName = $fileName
            FileSize = $fileSize
            ChunksUploaded = $chunkNumber
            Platform = $Platform
            Duration = ((Get-Date) - $uploadStartTime).TotalSeconds
        }
    }
    catch {
        if ($ShowProgress) {
            Write-Progress -Activity "[$platformDisplay] $fileName" -Id $ProgressId -Completed
        }
        if ($ProgressState) {
            $ProgressState[$Platform].Status = 'Failed'
        }
        Write-Action1Log "Software repository upload failed" -Level ERROR -ErrorRecord $_
        throw
    }
}
