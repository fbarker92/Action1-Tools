function Send-ChunkWithProgress {
    <#
    .SYNOPSIS
        Uploads a chunk using HttpClient with progress estimation during transfer.

    .DESCRIPTION
        Uses .NET HttpClient to upload data while providing estimated progress
        updates during the transfer. Since HttpClient doesn't provide true
        byte-level progress callbacks, this function estimates progress based
        on elapsed time and updates the progress bar smoothly.

    .PARAMETER Uri
        The URI to send the request to.

    .PARAMETER Headers
        Hashtable of headers to include (Authorization, Content-Range, etc.).

    .PARAMETER Data
        The byte array data to send.

    .PARAMETER ProgressParams
        Hashtable with progress display parameters:
        - Activity: Progress bar activity text
        - Id: Progress bar ID
        - FileOffset: Current offset in the overall file
        - FileSize: Total file size
        - ChunkNumber: Current chunk number
        - TotalChunks: Total number of chunks
        - UploadStartTime: DateTime when upload started

    .PARAMETER ShowProgress
        Whether to show progress bar updates.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [hashtable]$Headers,

        [Parameter(Mandatory)]
        [byte[]]$Data,

        [Parameter()]
        [hashtable]$ProgressParams,

        [Parameter()]
        [bool]$ShowProgress = $true
    )

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromMinutes(30)

    $dataStream = $null
    $content = $null
    $request = $null

    try {
        # Create the request
        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Put, $Uri)

        # Add headers (except Content-Type which goes on content)
        foreach ($key in $Headers.Keys) {
            if ($key -notin @('Content-Type', 'Content-Range')) {
                $null = $request.Headers.TryAddWithoutValidation($key, $Headers[$key])
            }
        }

        # Create content from data
        $dataStream = [System.IO.MemoryStream]::new($Data)
        $content = [System.Net.Http.StreamContent]::new($dataStream)

        # Set content headers
        $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
        if ($Headers['Content-Range']) {
            $null = $content.Headers.TryAddWithoutValidation('Content-Range', $Headers['Content-Range'])
        }

        $request.Content = $content

        $chunkSize = $Data.Length
        $chunkStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Start async upload
        $sendTask = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)

        # Animate progress while uploading
        $animationChars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
        $animIndex = 0

        # For first chunk or when we don't have speed data, estimate based on time within chunk
        # Assume ~2 MB/s baseline speed if no history (conservative estimate)
        $baselineSpeed = 2 * 1024 * 1024

        while (-not $sendTask.IsCompleted) {
            if ($ShowProgress -and $ProgressParams) {
                $totalElapsed = (Get-Date) - $ProgressParams.UploadStartTime
                $chunkElapsed = $chunkStopwatch.ElapsedMilliseconds / 1000.0

                # Calculate historical speed if we have prior data
                $historicalSpeed = if ($totalElapsed.TotalSeconds -gt 0 -and $ProgressParams.FileOffset -gt 0) {
                    $ProgressParams.FileOffset / $totalElapsed.TotalSeconds
                } else {
                    $baselineSpeed
                }

                # Estimate progress within this chunk
                # Use time-based animation: smoothly progress through the chunk
                # Estimate how long the chunk should take based on speed
                $estimatedChunkDuration = if ($historicalSpeed -gt 0) { $chunkSize / $historicalSpeed } else { 10 }
                $chunkProgress = [Math]::Min(0.95, $chunkElapsed / [Math]::Max(0.5, $estimatedChunkDuration))

                $estimatedChunkBytes = [long]($chunkSize * $chunkProgress)
                $estimatedTotalBytes = $ProgressParams.FileOffset + $estimatedChunkBytes

                $percentComplete = [int](($estimatedTotalBytes / $ProgressParams.FileSize) * 100)
                $percentComplete = [Math]::Max(1, [Math]::Min(99, $percentComplete))  # Keep between 1-99% during transfer

                $uploadedDisplay = ConvertTo-FileSize -Bytes ([long]$estimatedTotalBytes)
                $totalDisplay = ConvertTo-FileSize -Bytes $ProgressParams.FileSize

                # Show current speed estimate (if we have any data, otherwise show "calculating...")
                $currentSpeed = if ($chunkElapsed -gt 0.5) { $estimatedChunkBytes / $chunkElapsed } else { $historicalSpeed }
                $speedDisplay = if ($totalElapsed.TotalSeconds -lt 0.5 -and $ProgressParams.FileOffset -eq 0) {
                    "calculating..."
                } else {
                    "$(ConvertTo-FileSize -Bytes $currentSpeed)/s"
                }

                $remaining = if ($currentSpeed -gt 0) { ($ProgressParams.FileSize - $estimatedTotalBytes) / $currentSpeed } else { 0 }
                $remainingDisplay = if ($remaining -gt 60) { "{0:N0}m {1:N0}s" -f [Math]::Floor($remaining / 60), ($remaining % 60) } else { "{0:N0}s" -f $remaining }

                $spinner = $animationChars[$animIndex % $animationChars.Count]
                $animIndex++

                # Update file progress bar
                Write-Action1Progress `
                    -Activity $ProgressParams.Activity `
                    -Status "$spinner Chunk $($ProgressParams.ChunkNumber)/$($ProgressParams.TotalChunks) | $uploadedDisplay / $totalDisplay | $speedDisplay | ETA: $remainingDisplay" `
                    -PercentComplete $percentComplete `
                    -Id $ProgressParams.Id

                # Update overall progress bar if multi-file context provided
                if ($ProgressParams.OverallContext) {
                    $oc = $ProgressParams.OverallContext
                    $overallElapsed = (Get-Date) - $oc.StartTime
                    $overallEstimatedBytes = $oc.PriorBytes + $estimatedTotalBytes
                    $overallPercent = [int](($overallEstimatedBytes / $oc.TotalSize) * 100)
                    $overallPercent = [Math]::Max(1, [Math]::Min(99, $overallPercent))
                    $overallSpeed = if ($overallElapsed.TotalSeconds -gt 0) { $overallEstimatedBytes / $overallElapsed.TotalSeconds } else { $currentSpeed }
                    $overallSpeedDisplay = "$(ConvertTo-FileSize -Bytes $overallSpeed)/s"

                    Write-Action1Progress `
                        -Activity "Overall: $($oc.FileIndex) of $($oc.TotalFiles) files" `
                        -Status "$spinner $(ConvertTo-FileSize -Bytes $overallEstimatedBytes) / $(ConvertTo-FileSize -Bytes $oc.TotalSize) | $overallSpeedDisplay" `
                        -PercentComplete $overallPercent `
                        -Id 0
                }
            }

            Start-Sleep -Milliseconds 100
        }

        $chunkStopwatch.Stop()

        # Get the response
        $response = $sendTask.GetAwaiter().GetResult()

        # Read response content
        $responseContent = ""
        if ($response.Content) {
            $responseContent = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }

        # Build response headers hashtable
        $responseHeaders = @{}
        foreach ($header in $response.Headers) {
            $responseHeaders[$header.Key] = ($header.Value -join ', ')
        }
        if ($response.Content -and $response.Content.Headers) {
            foreach ($header in $response.Content.Headers) {
                $responseHeaders[$header.Key] = ($header.Value -join ', ')
            }
        }

        return @{
            StatusCode = [int]$response.StatusCode
            StatusDescription = $response.ReasonPhrase
            Content = $responseContent
            Headers = $responseHeaders
            ElapsedMilliseconds = $chunkStopwatch.ElapsedMilliseconds
        }
    }
    finally {
        if ($dataStream) { $dataStream.Dispose() }
        if ($content) { $content.Dispose() }
        if ($request) { $request.Dispose() }
        $client.Dispose()
        $handler.Dispose()
    }
}
