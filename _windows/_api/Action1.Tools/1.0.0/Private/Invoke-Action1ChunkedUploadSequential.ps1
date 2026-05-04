function Invoke-Action1ChunkedUploadSequential {
    <#
    .SYNOPSIS
        Sequential chunked upload (fallback for small files or when parallel is disabled).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter()]
        [int]$ChunkSizeMB = 5,

        [Parameter()]
        [hashtable]$AdditionalData
    )

    $fileInfo = Get-Item $FilePath
    $fileName = $fileInfo.Name
    $fileSize = $fileInfo.Length
    $chunkSize = $ChunkSizeMB * 1024 * 1024
    $totalChunks = [Math]::Ceiling($fileSize / $chunkSize)

    Write-Action1Log "Sequential chunked upload: $totalChunks chunks of $(ConvertTo-FileSize -Bytes $chunkSize)" -Level INFO

    try {
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        $uploadId = [Guid]::NewGuid().ToString()
        $currentChunk = 0

        Write-Action1Progress -Activity "Uploading $fileName" -Status "Initializing..." -PercentComplete 0 -Id 1

        while ($fileStream.Position -lt $fileStream.Length) {
            $currentChunk++
            $remainingBytes = $fileStream.Length - $fileStream.Position
            $currentChunkSize = [Math]::Min($chunkSize, $remainingBytes)

            $buffer = New-Object byte[] $currentChunkSize
            $bytesRead = $fileStream.Read($buffer, 0, $currentChunkSize)

            $overallPercent = [int](($fileStream.Position / $fileStream.Length) * 100)
            $uploadedSize = ConvertTo-FileSize -Bytes $fileStream.Position
            $totalSize = ConvertTo-FileSize -Bytes $fileSize

            Write-Action1Progress `
                -Activity "Uploading $fileName ($uploadedSize / $totalSize)" `
                -Status "Chunk $currentChunk of $totalChunks" `
                -PercentComplete $overallPercent `
                -Id 1

            # Show chunk progress as child progress bar
            Write-Action1Progress `
                -Activity "Current Chunk" `
                -Status "Encoding and uploading..." `
                -PercentComplete 0 `
                -Id 2 `
                -ParentId 1

            $base64Chunk = [Convert]::ToBase64String($buffer)

            Write-Action1Progress `
                -Activity "Current Chunk" `
                -Status "Uploading to server..." `
                -PercentComplete 50 `
                -Id 2 `
                -ParentId 1

            Write-Action1Log "Uploading chunk $currentChunk/$totalChunks ($(ConvertTo-FileSize -Bytes $bytesRead))" -Level DEBUG

            $chunkData = @{
                uploadId = $uploadId
                fileName = $fileName
                chunkNumber = $currentChunk
                totalChunks = $totalChunks
                chunkData = $base64Chunk
            }

            if ($currentChunk -eq 1 -and $AdditionalData) {
                foreach ($key in $AdditionalData.Keys) {
                    $chunkData[$key] = $AdditionalData[$key]
                }
            }

            $chunkResponse = Invoke-Action1ApiRequest -Endpoint "$Endpoint/chunk" -Method POST -Body $chunkData

            Write-Action1Progress `
                -Activity "Current Chunk" `
                -Status "Complete" `
                -PercentComplete 100 `
                -Id 2 `
                -ParentId 1

            Write-Action1Log "Chunk $currentChunk uploaded successfully" -Level TRACE -Data $chunkResponse

            Start-Sleep -Milliseconds 100
        }

        $fileStream.Close()
        $fileStream.Dispose()

        # Finalize upload
        Write-Action1Progress `
            -Activity "Uploading $fileName" `
            -Status "Finalizing upload..." `
            -PercentComplete 95 `
            -Id 1

        Write-Action1Log "Finalizing chunked upload" -Level INFO

        $finalizeData = @{
            uploadId = $uploadId
            fileName = $fileName
            totalChunks = $totalChunks
        }

        $response = Invoke-Action1ApiRequest -Endpoint "$Endpoint/finalize" -Method POST -Body $finalizeData

        Write-Action1Progress `
            -Activity "Uploading $fileName" `
            -Status "Complete" `
            -PercentComplete 100 `
            -Id 1

        Start-Sleep -Milliseconds 500
        Write-Progress -Activity "Uploading $fileName" -Id 1 -Completed
        Write-Progress -Activity "Current Chunk" -Id 2 -Completed

        Write-Action1Log "Sequential chunked upload completed successfully" -Level INFO
        return $response
    }
    catch {
        if ($fileStream) {
            $fileStream.Close()
            $fileStream.Dispose()
        }

        Write-Progress -Activity "Uploading $fileName" -Id 1 -Completed
        Write-Progress -Activity "Current Chunk" -Id 2 -Completed

        Write-Action1Log "Sequential chunked upload failed" -Level ERROR -ErrorRecord $_
        throw
    }
}
