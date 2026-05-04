function Invoke-Action1ChunkedUpload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter()]
        [int]$ChunkSizeMB = 5,

        [Parameter()]
        [hashtable]$AdditionalData,

        [Parameter()]
        [int]$ThrottleLimit = 4,

        [Parameter()]
        [switch]$Sequential
    )

    $fileInfo = Get-Item $FilePath
    $fileName = $fileInfo.Name
    $fileSize = $fileInfo.Length
    $chunkSize = $ChunkSizeMB * 1024 * 1024
    $totalChunks = [Math]::Ceiling($fileSize / $chunkSize)

    # Use sequential for small files (< 5 chunks) or if explicitly requested
    if ($Sequential -or $totalChunks -lt 5) {
        return Invoke-Action1ChunkedUploadSequential -FilePath $FilePath -Endpoint $Endpoint -ChunkSizeMB $ChunkSizeMB -AdditionalData $AdditionalData
    }

    Write-Action1Log "Parallel chunked upload: $totalChunks chunks of $(ConvertTo-FileSize -Bytes $chunkSize) (ThrottleLimit: $ThrottleLimit)" -Level INFO

    $uploadId = [Guid]::NewGuid().ToString()

    try {
        # Pre-read all chunks into memory (required for parallel processing)
        Write-Action1Progress -Activity "Uploading $fileName" -Status "Reading file chunks..." -PercentComplete 0 -Id 1
        Write-Action1Log "Pre-reading file chunks into memory..." -Level DEBUG

        $chunks = @()
        $fileStream = [System.IO.File]::OpenRead($FilePath)

        for ($i = 1; $i -le $totalChunks; $i++) {
            $remainingBytes = $fileStream.Length - $fileStream.Position
            $currentChunkSize = [Math]::Min($chunkSize, $remainingBytes)

            $buffer = New-Object byte[] $currentChunkSize
            $null = $fileStream.Read($buffer, 0, $currentChunkSize)

            $chunks += @{
                ChunkNumber = $i
                Data = [Convert]::ToBase64String($buffer)
                Size = $currentChunkSize
            }

            $readPercent = [int](($i / $totalChunks) * 25)  # Reading is 0-25%
            Write-Action1Progress -Activity "Uploading $fileName" -Status "Reading chunk $i of $totalChunks..." -PercentComplete $readPercent -Id 1
        }

        $fileStream.Close()
        $fileStream.Dispose()
        $fileStream = $null

        Write-Action1Log "All $totalChunks chunks read into memory" -Level DEBUG

        # Prepare data needed for parallel execution
        $baseUri = $script:Action1BaseUri
        $token = Get-Action1AccessToken
        $chunkEndpoint = "$Endpoint/chunk"

        # Thread-safe dictionary to track chunk status: 0=pending, 1=uploading, 2=complete, -1=failed
        $chunkStatus = [System.Collections.Concurrent.ConcurrentDictionary[int, int]]::new()
        for ($i = 1; $i -le $totalChunks; $i++) {
            $null = $chunkStatus.TryAdd($i, 0)
        }

        # Track which slots (progress bar IDs) are assigned to which chunks
        $slotAssignments = [System.Collections.Concurrent.ConcurrentDictionary[int, int]]::new()

        Write-Action1Progress -Activity "Uploading $fileName" -Status "Uploading $totalChunks chunks in parallel..." -PercentComplete 25 -Id 1

        # Start a background runspace to update progress bars
        $progressRunspace = [runspacefactory]::CreateRunspace()
        $progressRunspace.Open()
        $progressRunspace.SessionStateProxy.SetVariable('chunkStatus', $chunkStatus)
        $progressRunspace.SessionStateProxy.SetVariable('slotAssignments', $slotAssignments)
        $progressRunspace.SessionStateProxy.SetVariable('totalChunks', $totalChunks)
        $progressRunspace.SessionStateProxy.SetVariable('fileName', $fileName)
        $progressRunspace.SessionStateProxy.SetVariable('throttleLimit', $ThrottleLimit)
        $progressRunspace.SessionStateProxy.SetVariable('chunkSize', $chunkSize)

        $progressScript = {
            while ($true) {
                $completedCount = ($chunkStatus.Values | Where-Object { $_ -eq 2 }).Count
                $failedCount = ($chunkStatus.Values | Where-Object { $_ -eq -1 }).Count
                $uploadingChunks = $chunkStatus.GetEnumerator() | Where-Object { $_.Value -eq 1 } | Select-Object -ExpandProperty Key

                # Update main progress bar (ID 1)
                $overallPercent = 25 + [int](($completedCount / $totalChunks) * 70)  # 25-95%
                $status = "Completed: $completedCount/$totalChunks"
                if ($failedCount -gt 0) { $status += " (Failed: $failedCount)" }
                Write-Progress -Activity "Uploading $fileName" -Status $status -PercentComplete $overallPercent -Id 1

                # Update individual chunk progress bars (IDs 10-1x based on throttle limit)
                $slot = 0
                foreach ($chunkNum in ($uploadingChunks | Sort-Object | Select-Object -First $throttleLimit)) {
                    $slot++
                    $progressId = 10 + $slot
                    $chunkSizeMB = [math]::Round($chunkSize / 1MB, 1)
                    Write-Progress -Activity "Chunk $chunkNum" -Status "Uploading ($chunkSizeMB MB)..." -PercentComplete 50 -Id $progressId -ParentId 1
                    $null = $slotAssignments.AddOrUpdate($chunkNum, $progressId, { param($k, $v) $progressId })
                }

                # Clear progress bars for completed chunks
                foreach ($entry in $slotAssignments.GetEnumerator()) {
                    $chunkNum = $entry.Key
                    $progressId = $entry.Value
                    $status = 0
                    if ($chunkStatus.TryGetValue($chunkNum, [ref]$status) -and ($status -eq 2 -or $status -eq -1)) {
                        Write-Progress -Activity "Chunk $chunkNum" -Id $progressId -Completed
                        $null = $slotAssignments.TryRemove($chunkNum, [ref]$null)
                    }
                }

                # Exit when all chunks are done
                if (($completedCount + $failedCount) -ge $totalChunks) {
                    # Clear any remaining progress bars
                    for ($i = 11; $i -le (10 + $throttleLimit); $i++) {
                        Write-Progress -Activity "Chunk" -Id $i -Completed
                    }
                    break
                }

                Start-Sleep -Milliseconds 200
            }
        }

        $progressPipeline = $progressRunspace.CreatePipeline()
        $progressPipeline.Commands.AddScript($progressScript)
        $progressHandle = $progressPipeline.BeginInvoke()

        # Upload chunks in parallel
        $uploadResults = $chunks | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            $chunk = $_
            $uploadIdLocal = $using:uploadId
            $fileNameLocal = $using:fileName
            $totalChunksLocal = $using:totalChunks
            $baseUriLocal = $using:baseUri
            $tokenLocal = $using:token
            $endpointLocal = $using:chunkEndpoint
            $additionalDataLocal = $using:AdditionalData
            $statusDict = $using:chunkStatus

            # Mark as uploading
            $null = $statusDict.TryUpdate($chunk.ChunkNumber, 1, 0)

            $chunkData = @{
                uploadId = $uploadIdLocal
                fileName = $fileNameLocal
                chunkNumber = $chunk.ChunkNumber
                totalChunks = $totalChunksLocal
                chunkData = $chunk.Data
            }

            # Add additional data to first chunk only
            if ($chunk.ChunkNumber -eq 1 -and $additionalDataLocal) {
                foreach ($key in $additionalDataLocal.Keys) {
                    $chunkData[$key] = $additionalDataLocal[$key]
                }
            }

            $uri = "$baseUriLocal/$endpointLocal"
            $headers = @{
                'Authorization' = "Bearer $tokenLocal"
                'Content-Type'  = 'application/json'
                'Accept'        = 'application/json'
            }

            try {
                $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body ($chunkData | ConvertTo-Json -Depth 10) -ErrorAction Stop

                # Mark as complete
                $null = $statusDict.TryUpdate($chunk.ChunkNumber, 2, 1)

                return @{
                    ChunkNumber = $chunk.ChunkNumber
                    Success = $true
                    Response = $response
                }
            }
            catch {
                # Mark as failed
                $null = $statusDict.TryUpdate($chunk.ChunkNumber, -1, 1)

                return @{
                    ChunkNumber = $chunk.ChunkNumber
                    Success = $false
                    Error = $_.Exception.Message
                }
            }
        }

        # Wait for progress runspace to finish
        $null = $progressPipeline.EndInvoke($progressHandle)
        $progressPipeline.Dispose()
        $progressRunspace.Close()
        $progressRunspace.Dispose()

        # Check for failures
        $failures = $uploadResults | Where-Object { -not $_.Success }
        if ($failures) {
            $failedChunks = ($failures | ForEach-Object { $_.ChunkNumber }) -join ', '
            throw "Failed to upload chunks: $failedChunks. Errors: $(($failures | ForEach-Object { $_.Error }) -join '; ')"
        }

        Write-Action1Log "All $totalChunks chunks uploaded successfully" -Level INFO

        # Finalize upload
        Write-Action1Progress -Activity "Uploading $fileName" -Status "Finalizing upload..." -PercentComplete 95 -Id 1
        Write-Action1Log "Finalizing chunked upload" -Level INFO

        $finalizeData = @{
            uploadId = $uploadId
            fileName = $fileName
            totalChunks = $totalChunks
        }

        $response = Invoke-Action1ApiRequest -Endpoint "$Endpoint/finalize" -Method POST -Body $finalizeData

        Write-Action1Progress -Activity "Uploading $fileName" -Status "Complete" -PercentComplete 100 -Id 1
        Start-Sleep -Milliseconds 500
        Write-Progress -Activity "Uploading $fileName" -Id 1 -Completed

        Write-Action1Log "Parallel chunked upload completed successfully" -Level INFO
        return $response
    }
    catch {
        if ($fileStream) {
            $fileStream.Close()
            $fileStream.Dispose()
        }

        # Clean up progress bars
        Write-Progress -Activity "Uploading $fileName" -Id 1 -Completed
        for ($i = 11; $i -le (10 + $ThrottleLimit); $i++) {
            Write-Progress -Activity "Chunk" -Id $i -Completed
        }

        Write-Action1Log "Parallel chunked upload failed" -Level ERROR -ErrorRecord $_
        throw
    }
}
