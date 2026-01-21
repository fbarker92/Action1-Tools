#Requires -Version 7.0

# Module-level variables
$script:Action1Region = $null
$script:Action1BaseUri = $null
$script:Action1ClientId = $null
$script:Action1ClientSecret = $null
$script:Action1AccessToken = $null
$script:Action1TokenExpiry = $null

# Region to API URL mapping
$script:Action1RegionUrls = @{
    'NorthAmerica' = 'https://app.action1.com/api/3.0'
    'Europe'       = 'https://app.eu.action1.com/api/3.0'
    'Australia'    = 'https://app.au.action1.com/api/3.0'
}
$script:DefaultMsiSwitches = "/qn /norestart"
$script:LogLevel = "INFO"
$script:LogFilePath = $null
$script:LogLevels = @{
    TRACE = 0
    DEBUG = 1
    INFO = 2
    WARN = 3
    ERROR = 4
}

#region Logging Functions

function Write-Action1Log {
    <#
    .SYNOPSIS
        Internal logging function for the module.
    
    .DESCRIPTION
        Provides structured logging with levels: TRACE, DEBUG, INFO, WARN, ERROR
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',
        
        [Parameter()]
        [object]$Data,
        
        [Parameter()]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )
    
    # Check if this log level should be displayed
    if ($script:LogLevels[$Level] -lt $script:LogLevels[$script:LogLevel]) {
        return
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $callerInfo = (Get-PSCallStack)[1]
    $caller = "$($callerInfo.Command)"
    
    # Build log message
    $logMessage = "[$timestamp] [$Level] [$caller] $Message"
    
    # Color coding for console output
    $color = switch ($Level) {
        'TRACE' { 'Gray' }
        'DEBUG' { 'Cyan' }
        'INFO' { 'White' }
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
    }
    
    # Write to console
    Write-Host $logMessage -ForegroundColor $color
    
    # Add data if provided
    if ($Data) {
        $dataString = $Data | ConvertTo-Json -Depth 5 -Compress
        $dataMessage = "[$timestamp] [$Level] [$caller] DATA: $dataString"
        Write-Host $dataMessage -ForegroundColor DarkGray
        $logMessage += "`n$dataMessage"
    }
    
    # Add error details if provided
    if ($ErrorRecord) {
        $errorMessage = "[$timestamp] [$Level] [$caller] ERROR DETAILS: $($ErrorRecord.Exception.Message)"
        $errorMessage += "`n  at $($ErrorRecord.InvocationInfo.ScriptName):$($ErrorRecord.InvocationInfo.ScriptLineNumber)"
        if ($ErrorRecord.Exception.StackTrace) {
            $errorMessage += "`n  StackTrace: $($ErrorRecord.Exception.StackTrace)"
        }
        Write-Host $errorMessage -ForegroundColor Red
        $logMessage += "`n$errorMessage"
    }
    
    # Write to log file if configured
    if ($script:LogFilePath) {
        try {
            $logMessage | Add-Content -Path $script:LogFilePath -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file: $($_.Exception.Message)"
        }
    }
}

function Set-Action1LogLevel {
    <#
    .SYNOPSIS
        Sets the logging level for the module.
    
    .DESCRIPTION
        Controls which log messages are displayed based on severity.
        TRACE (most verbose) > DEBUG > INFO > WARN > ERROR (least verbose)
    
    .PARAMETER Level
        The minimum log level to display.
    
    .PARAMETER LogFile
        Optional path to write logs to a file.
    
    .EXAMPLE
        Set-Action1LogLevel -Level DEBUG
    
    .EXAMPLE
        Set-Action1LogLevel -Level TRACE -LogFile "C:\Logs\action1-deployment.log"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level,
        
        [Parameter()]
        [string]$LogFile
    )

    # Set default log file path cross-platform
    if (-not $LogFile) {
        $tempDir = if ($ENV:TEMP) { $ENV:TEMP } elseif ($ENV:TMPDIR) { $ENV:TMPDIR } else { "/tmp" }
        $LogFile = Join-Path $tempDir "action1-deployment.log"
    }
    
    $script:LogLevel = $Level
    Write-Host "Log level set to: $Level" -ForegroundColor Green
    
    if ($LogFile) {
        $script:LogFilePath = $LogFile
        
        # Create log directory if it doesn't exist
        $logDir = Split-Path $LogFile -Parent
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        # Initialize log file
        $header = @"
==============================================
Action1 Deployment Log
Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Log Level: $Level
==============================================

"@
        $header | Set-Content -Path $LogFile
        Write-Host "Logging to file: $LogFile" -ForegroundColor Green
    }
}

function Get-Action1LogLevel {
    <#
    .SYNOPSIS
        Gets the current logging level.
    
    .EXAMPLE
        Get-Action1LogLevel
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "Current log level: $script:LogLevel" -ForegroundColor Cyan
    if ($script:LogFilePath) {
        Write-Host "Log file: $script:LogFilePath" -ForegroundColor Cyan
    }
    
    return @{
        Level = $script:LogLevel
        LogFile = $script:LogFilePath
    }
}

#endregion

#region Progress and UI Functions

function Start-Action1Spinner {
    <#
    .SYNOPSIS
        Starts an animated spinner for long-running operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter(Mandatory)]
        [ref]$SpinnerJob
    )
    
    $spinnerScript = {
        param($msg)
        $spinChars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
        $i = 0
        while ($true) {
            Write-Host "`r$msg $($spinChars[$i % $spinChars.Length]) " -NoNewline -ForegroundColor Cyan
            Start-Sleep -Milliseconds 100
            $i++
        }
    }
    
    $SpinnerJob.Value = Start-Job -ScriptBlock $spinnerScript -ArgumentList $Message
}

function Stop-Action1Spinner {
    <#
    .SYNOPSIS
        Stops the animated spinner.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $SpinnerJob,
        
        [Parameter()]
        [string]$CompletionMessage = "Done"
    )
    
    if ($SpinnerJob) {
        Stop-Job $SpinnerJob -ErrorAction SilentlyContinue
        Remove-Job $SpinnerJob -ErrorAction SilentlyContinue
        Write-Host "`r$CompletionMessage                    " -ForegroundColor Green
    }
}

function Write-Action1Progress {
    <#
    .SYNOPSIS
        Displays progress bar for operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Activity,
        
        [Parameter()]
        [string]$Status = "Processing",
        
        [Parameter(Mandatory)]
        [int]$PercentComplete,
        
        [Parameter()]
        [int]$Id = 0,
        
        [Parameter()]
        [int]$ParentId = -1
    )
    
    $params = @{
        Activity = $Activity
        Status = $Status
        PercentComplete = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
        Id = $Id
    }
    
    if ($ParentId -ge 0) {
        $params['ParentId'] = $ParentId
    }
    
    Write-Progress @params
}

function ConvertTo-FileSize {
    <#
    .SYNOPSIS
        Converts bytes to human-readable file size.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [long]$Bytes
    )
    
    $sizes = @('B', 'KB', 'MB', 'GB', 'TB')
    $order = 0
    $value = $Bytes
    
    while ($value -ge 1024 -and $order -lt $sizes.Length - 1) {
        $value = $value / 1024
        $order++
    }
    
    return "{0:N2} {1}" -f $value, $sizes[$order]
}

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
        [int]$ChunkSizeMB = 5,
        
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
    
    # For small files (< 10MB), upload directly
    if ($fileSize -lt (10 * 1024 * 1024)) {
        Write-Action1Log "File is small, uploading directly without chunking" -Level DEBUG
        return Invoke-Action1DirectUpload -FilePath $FilePath -Endpoint $Endpoint -AdditionalData $AdditionalData
    }
    
    # For large files, use chunked upload
    Write-Action1Log "File is large, using chunked upload" -Level DEBUG
    return Invoke-Action1ChunkedUpload -FilePath $FilePath -Endpoint $Endpoint -ChunkSizeMB $ChunkSizeMB -AdditionalData $AdditionalData
}

function Invoke-Action1DirectUpload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [string]$Endpoint,
        
        [Parameter()]
        [hashtable]$AdditionalData
    )
    
    $fileInfo = Get-Item $FilePath
    $fileName = $fileInfo.Name
    $fileSize = $fileInfo.Length
    
    Write-Action1Progress -Activity "Uploading $fileName" -Status "Reading file..." -PercentComplete 0 -Id 1
    
    try {
        $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
        Write-Action1Log "File read into memory: $(ConvertTo-FileSize -Bytes $fileBytes.Length)" -Level DEBUG
        
        Write-Action1Progress -Activity "Uploading $fileName" -Status "Encoding..." -PercentComplete 25 -Id 1
        
        $base64Content = [Convert]::ToBase64String($fileBytes)
        Write-Action1Log "File encoded to base64: $($base64Content.Length) characters" -Level DEBUG
        
        Write-Action1Progress -Activity "Uploading $fileName" -Status "Uploading to Action1..." -PercentComplete 50 -Id 1
        
        $uploadData = @{
            fileName = $fileName
            fileData = $base64Content
        }
        
        if ($AdditionalData) {
            foreach ($key in $AdditionalData.Keys) {
                $uploadData[$key] = $AdditionalData[$key]
            }
        }
        
        $response = Invoke-Action1ApiRequest -Endpoint $Endpoint -Method POST -Body $uploadData
        
        Write-Action1Progress -Activity "Uploading $fileName" -Status "Complete" -PercentComplete 100 -Id 1
        Start-Sleep -Milliseconds 500
        Write-Progress -Activity "Uploading $fileName" -Id 1 -Completed
        
        Write-Action1Log "File uploaded successfully" -Level INFO
        return $response
    }
    catch {
        Write-Progress -Activity "Uploading $fileName" -Id 1 -Completed
        Write-Action1Log "Direct upload failed" -Level ERROR -ErrorRecord $_
        throw
    }
}

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

#endregion

#region Helper Functions

function Get-Action1AccessToken {
    <#
    .SYNOPSIS
        Obtains an OAuth2 access token from the Action1 API.
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    # Check if we have a valid token already
    if (-not $Force -and $script:Action1AccessToken -and $script:Action1TokenExpiry -and (Get-Date) -lt $script:Action1TokenExpiry) {
        Write-Action1Log "Using cached access token (expires: $($script:Action1TokenExpiry))" -Level DEBUG
        return $script:Action1AccessToken
    }

    if (-not $script:Action1ClientId -or -not $script:Action1ClientSecret) {
        Write-Action1Log "API credentials not configured" -Level ERROR
        throw "Action1 API credentials not set. Please run Set-Action1ApiCredentials first."
    }

    if (-not $script:Action1BaseUri) {
        Write-Action1Log "API base URI not configured" -Level ERROR
        throw "Action1 API base URI not set. Please run Set-Action1ApiCredentials first."
    }

    Write-Action1Log "Requesting OAuth2 access token..." -Level INFO

    $tokenUrl = "$($script:Action1BaseUri)/oauth2/token"
    $body = @{
        client_id     = $script:Action1ClientId
        client_secret = $script:Action1ClientSecret
    }

    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body ($body | ConvertTo-Json) -ContentType 'application/json' -ErrorAction Stop

        $script:Action1AccessToken = $response.access_token

        # Set token expiry (default to 1 hour if not provided, subtract 5 minutes for safety)
        $expiresIn = if ($response.expires_in) { $response.expires_in - 300 } else { 3300 }
        $script:Action1TokenExpiry = (Get-Date).AddSeconds($expiresIn)

        Write-Action1Log "Access token obtained successfully (expires in $expiresIn seconds)" -Level INFO
        return $script:Action1AccessToken
    }
    catch {
        Write-Action1Log "Failed to obtain access token" -Level ERROR -ErrorRecord $_
        throw "Authentication failed: $($_.Exception.Message)"
    }
}

function Get-Action1Headers {
    [CmdletBinding()]
    param()

    Write-Action1Log "Generating authentication headers" -Level TRACE

    # Get or refresh the access token
    $token = Get-Action1AccessToken

    Write-Action1Log "Authentication headers generated successfully" -Level DEBUG

    return @{
        'Authorization' = "Bearer $token"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }
}

function Invoke-Action1ApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,
        
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'PATCH')]
        [string]$Method,
        
        [Parameter()]
        [hashtable]$Body,
        
        [Parameter()]
        [hashtable]$QueryParameters
    )
    
    $headers = Get-Action1Headers
    $uri = "$script:Action1BaseUri/$Endpoint"
    
    if ($QueryParameters) {
        $queryString = ($QueryParameters.GetEnumerator() | ForEach-Object {
            "$($_.Key)=$([uri]::EscapeDataString($_.Value))"
        }) -join '&'
        $uri = "$uri`?$queryString"
    }
    
    Write-Action1Log "Preparing API request: $Method $uri" -Level DEBUG
    if ($QueryParameters) {
        Write-Action1Log "Query parameters" -Level TRACE -Data $QueryParameters
    }
    
    $params = @{
        Uri = $uri
        Method = $Method
        Headers = $headers
        ErrorAction = 'Stop'
    }
    
    if ($Body) {
        $bodyJson = ($Body | ConvertTo-Json -Depth 10)
        $params['Body'] = $bodyJson
        Write-Action1Log "Request body" -Level TRACE -Data $Body
    }
    
    try {
        Write-Action1Log "Executing API request..." -Level INFO
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $response = Invoke-RestMethod @params
        
        $stopwatch.Stop()
        Write-Action1Log "API request completed successfully in $($stopwatch.ElapsedMilliseconds)ms" -Level INFO
        Write-Action1Log "Response data" -Level TRACE -Data $response
        
        return $response
    }
    catch {
        Write-Action1Log "API request failed" -Level ERROR -ErrorRecord $_
        
        if ($_.ErrorDetails.Message) {
            Write-Action1Log "Error details from API" -Level ERROR -Data ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue)
        }
        
        throw
    }
}

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

#endregion

#region Public Functions

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
        Write-Host "  [1] NorthAmerica (app.action1.com)"
        Write-Host "  [2] Europe (app.eu.action1.com)"
        Write-Host "  [3] Australia (app.au.action1.com)"

        $selection = Read-Host "`nEnter selection (1-3)"
        $Region = switch ($selection) {
            '1' { 'NorthAmerica' }
            '2' { 'Europe' }
            '3' { 'Australia' }
            default {
                Write-Warning "Invalid selection. Defaulting to NorthAmerica."
                'NorthAmerica'
            }
        }
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

        $profilePath = if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
            "$env:LOCALAPPDATA\Action1AppDeployment"
        } else {
            "$HOME/.action1"
        }

        Write-Action1Log "Profile path: $profilePath" -Level DEBUG

        if (-not (Test-Path $profilePath)) {
            Write-Action1Log "Creating profile directory" -Level DEBUG
            New-Item -Path $profilePath -ItemType Directory -Force | Out-Null
        }

        $credFile = Join-Path $profilePath "credentials.json"

        try {
            @{
                ClientId = $ClientId
                ClientSecret = $ClientSecret
                Region = $Region
            } | ConvertTo-Json | Set-Content $credFile -Force

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

function Test-Action1Connection {
    <#
    .SYNOPSIS
        Tests the connection to Action1 API.
    
    .DESCRIPTION
        Validates that the API credentials are correct and the API is accessible.
    
    .EXAMPLE
        Test-Action1Connection
    #>
    [CmdletBinding()]
    param()
    
    Write-Action1Log "Testing Action1 API connection" -Level INFO
    
    try {
        Write-Action1Log "Attempting to query organizations endpoint" -Level DEBUG
        # Try to list organizations (lightweight API call)
        $response = Invoke-Action1ApiRequest -Endpoint "organizations" -Method GET
        
        Write-Action1Log "API connection test successful" -Level INFO
        Write-Action1Log "Organizations retrieved" -Level TRACE -Data $response
        
        Write-Host "✓ Successfully connected to Action1 API" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Action1Log "API connection test failed" -Level ERROR -ErrorRecord $_
        Write-Host "✗ Failed to connect to Action1 API" -ForegroundColor Red
        return $false
    }
}

function New-Action1AppRepo {
    <#
    .SYNOPSIS
        Creates a new Action1 application repository structure.

    .DESCRIPTION
        Initializes a new directory structure for managing Action1 application deployments,
        including folders for installers, scripts, and a manifest file.

    .PARAMETER AppName
        The name of the application.

    .PARAMETER Path
        The path where the repository should be created. Defaults to current directory.

    .PARAMETER IncludeExamples
        If specified, includes example files and documentation.

    .EXAMPLE
        New-Action1AppRepo -AppName "7-Zip" -Path "C:\Apps"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,
        
        [Parameter()]
        [string]$Path = (Get-Location).Path,
        
        [Parameter()]
        [switch]$IncludeExamples
    )
    
    Write-Action1Log "Creating new Action1 app repository for: $AppName" -Level INFO
    Write-Action1Log "Base path: $Path" -Level DEBUG
    Write-Action1Log "Include examples: $IncludeExamples" -Level DEBUG
    
    $sanitizedName = $AppName -replace '[\\/:*?"<>|]', '_'
    Write-Action1Log "Sanitized app name: $sanitizedName" -Level DEBUG
    
    $repoPath = Join-Path $Path $sanitizedName
    Write-Action1Log "Repository path: $repoPath" -Level INFO
    
    # Create directory structure
    $directories = @(
        $repoPath,
        (Join-Path $repoPath "installers"),
        (Join-Path $repoPath "scripts"),
        (Join-Path $repoPath "documentation")
    )
    
    Write-Action1Log "Creating directory structure" -Level INFO
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            Write-Action1Log "Creating directory: $dir" -Level DEBUG
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        } else {
            Write-Action1Log "Directory already exists: $dir" -Level WARN
        }
    }
    
    # Create initial manifest
    $manifest = [PSCustomObject]@{
        AppName = $AppName
        Publisher = ""
        Description = ""
        Version = "1.0.0"
        CreatedDate = Get-Date -Format "yyyy-MM-dd"
        LastModified = Get-Date -Format "yyyy-MM-dd"
        InstallerType = "msi"  # msi, exe, ps1
        InstallerFileName = ""
        InstallSwitches = ""
        UninstallSwitches = ""
        DetectionMethod = @{
            Type = "registry"  # registry, file, script
            Path = ""
            Value = ""
        }
        Requirements = @{
            OSVersion = ""
            Architecture = "x64"
            MinDiskSpaceMB = 0
            MinMemoryMB = 0
        }
        Action1Config = @{
            OrganizationId = ""
            PackageId = ""
            PolicyId = ""
            DeploymentGroup = ""
        }
        Metadata = @{
            Tags = @()
            Notes = ""
        }
    }
    
    $manifestPath = Join-Path $repoPath "manifest.json"
    Write-ManifestFile -Manifest $manifest -Path $manifestPath
    
    # Create README
    Write-Action1Log "Creating README file" -Level DEBUG
    $readme = @"
# $AppName - Action1 Deployment Package

## Overview
This repository contains the deployment package for $AppName.

## Structure
- **installers/** - Application installer files
- **scripts/** - Pre/post installation scripts
- **documentation/** - Additional documentation
- **manifest.json** - Application deployment configuration

## Usage
1. Place your installer in the `installers/` folder
2. Update `manifest.json` with application details
3. Run ``Package-Action1App -ManifestPath ".\manifest.json"``
4. Deploy using ``Deploy-Action1App -ManifestPath ".\manifest.json"``

## Deployment Commands
``````powershell
# Package the application
Package-Action1App -ManifestPath ".\manifest.json"

# Deploy new application
Deploy-Action1App -ManifestPath ".\manifest.json"

# Deploy update to existing application
Deploy-Action1AppUpdate -ManifestPath ".\manifest.json"
``````

Created: $(Get-Date -Format "yyyy-MM-dd")
"@
    
    $readme | Set-Content (Join-Path $repoPath "README.md") -Force
    
    if ($IncludeExamples) {
        Write-Action1Log "Creating example scripts" -Level INFO
        # Create example pre-install script
        $preInstallExample = @"
# Example pre-installation script
# This runs before the main installer

Write-Host "Running pre-installation tasks..."

# Example: Stop a service
# Stop-Service -Name "ServiceName" -ErrorAction SilentlyContinue

# Example: Backup configuration
# Copy-Item "C:\ProgramData\AppConfig" "C:\Backup\AppConfig" -Recurse -Force

Write-Host "Pre-installation complete."
"@
        $preInstallExample | Set-Content (Join-Path $repoPath "scripts" "pre-install.ps1") -Force
        Write-Action1Log "Created pre-install example script" -Level DEBUG
        
        # Create example post-install script
        $postInstallExample = @"
# Example post-installation script
# This runs after the main installer

Write-Host "Running post-installation tasks..."

# Example: Configure application
# New-Item -Path "C:\ProgramData\AppConfig" -ItemType Directory -Force
# Set-Content "C:\ProgramData\AppConfig\settings.cfg" "config=value"

# Example: Start a service
# Start-Service -Name "ServiceName" -ErrorAction SilentlyContinue

Write-Host "Post-installation complete."
"@
        $postInstallExample | Set-Content (Join-Path $repoPath "scripts" "post-install.ps1") -Force
        Write-Action1Log "Created post-install example script" -Level DEBUG
    }
    
    Write-Action1Log "Repository creation completed successfully" -Level INFO
    Write-Host "`n✓ Action1 app repository created successfully!" -ForegroundColor Green
    Write-Host "Location: $repoPath" -ForegroundColor Cyan
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "1. Place your installer in: $(Join-Path $repoPath 'installers')"
    Write-Host "2. Edit manifest.json to configure deployment settings"
    Write-Host "3. Run New-Action1AppPackage to prepare for deployment"
    
    return $repoPath
}

function New-Action1AppPackage {
    <#
    .SYNOPSIS
        Packages an application for Action1 deployment.

    .DESCRIPTION
        Prepares an application package by gathering installer information,
        prompting for installation switches, and updating the manifest file.

    .PARAMETER ManifestPath
        Path to the manifest.json file.

    .PARAMETER Interactive
        If specified, prompts user for all configuration options.

    .EXAMPLE
        New-Action1AppPackage -ManifestPath ".\7-Zip\manifest.json" -Interactive
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,
        
        [Parameter()]
        [switch]$Interactive
    )
    
    Write-Host "`n=== Action1 Application Packager ===" -ForegroundColor Cyan
    
    # Load manifest
    $manifest = Read-ManifestFile -Path $ManifestPath
    $repoPath = Split-Path $ManifestPath -Parent
    $installersPath = Join-Path $repoPath "installers"
    
    # Find installer files
    $installerFiles = Get-ChildItem -Path $installersPath -File -ErrorAction SilentlyContinue
    
    if (-not $installerFiles) {
        Write-Warning "No installer files found in $installersPath"
        Write-Host "Please place your installer file in the installers directory."
        return
    }
    
    # If multiple installers, let user choose
    if ($installerFiles.Count -gt 1) {
        Write-Host "`nMultiple installer files found:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $installerFiles.Count; $i++) {
            Write-Host "  [$($i+1)] $($installerFiles[$i].Name) ($([math]::Round($installerFiles[$i].Length / 1MB, 2)) MB)"
        }
        $selection = Read-Host "`nSelect installer number"
        $installerFile = $installerFiles[$selection - 1]
    } else {
        $installerFile = $installerFiles[0]
    }
    
    Write-Host "`nSelected installer: $($installerFile.Name)" -ForegroundColor Green
    
    # Determine installer type
    $installerType = switch ($installerFile.Extension.ToLower()) {
        '.msi' { 'msi' }
        '.exe' { 'exe' }
        '.ps1' { 'powershell' }
        default { 'unknown' }
    }
    
    $manifest.InstallerType = $installerType
    $manifest.InstallerFileName = $installerFile.Name
    
    # Interactive configuration
    if ($Interactive) {
        Write-Host "`n--- Application Information ---" -ForegroundColor Cyan
        
        $appName = Read-Host "Application Name [$($manifest.AppName)]"
        if ($appName) { $manifest.AppName = $appName }
        
        $publisher = Read-Host "Publisher [$($manifest.Publisher)]"
        if ($publisher) { $manifest.Publisher = $publisher }
        
        $version = Read-Host "Version [$($manifest.Version)]"
        if ($version) { $manifest.Version = $version }
        
        $description = Read-Host "Description [$($manifest.Description)]"
        if ($description) { $manifest.Description = $description }
        
        Write-Host "`n--- Installation Configuration ---" -ForegroundColor Cyan
        
        # Install switches based on type
        if ($installerType -eq 'msi') {
            Write-Host "`nDefault MSI switches: $script:DefaultMsiSwitches (automatically added by Action1)"
            Write-Host "You can add additional switches if needed."
            $additionalSwitches = Read-Host "Additional install switches (optional)"
            if ($additionalSwitches) {
                $manifest.InstallSwitches = $additionalSwitches
            } else {
                $manifest.InstallSwitches = ""
            }
        } elseif ($installerType -eq 'exe') {
            Write-Host "`nCommon silent install switches:"
            Write-Host "  /S or /silent - Generic silent"
            Write-Host "  /quiet /norestart - Many installers"
            Write-Host "  /verysilent /norestart - Inno Setup"
            Write-Host "  -q -norestart - Some installers"
            $installSwitches = Read-Host "Install switches [$($manifest.InstallSwitches)]"
            if ($installSwitches) { $manifest.InstallSwitches = $installSwitches }
        }
        
        $uninstallSwitches = Read-Host "Uninstall switches [$($manifest.UninstallSwitches)]"
        if ($uninstallSwitches) { $manifest.UninstallSwitches = $uninstallSwitches }
        
        Write-Host "`n--- Detection Method ---" -ForegroundColor Cyan
        Write-Host "How should Action1 detect if this app is installed?"
        Write-Host "  [1] Registry key"
        Write-Host "  [2] File path"
        Write-Host "  [3] Custom script"
        $detectionChoice = Read-Host "Choice [1]"
        
        switch ($detectionChoice) {
            '2' {
                $manifest.DetectionMethod.Type = 'file'
                $filePath = Read-Host "File path to check"
                $manifest.DetectionMethod.Path = $filePath
            }
            '3' {
                $manifest.DetectionMethod.Type = 'script'
                Write-Host "A detection script file will need to be created in the scripts folder."
                $manifest.DetectionMethod.Path = (Join-Path "scripts" "detect.ps1")
            }
            default {
                $manifest.DetectionMethod.Type = 'registry'
                $regPath = Read-Host "Registry path [$($manifest.DetectionMethod.Path)]"
                if ($regPath) { $manifest.DetectionMethod.Path = $regPath }
            }
        }
        
        Write-Host "`n--- System Requirements ---" -ForegroundColor Cyan
        $arch = Read-Host "Architecture (x86/x64/both) [$($manifest.Requirements.Architecture)]"
        if ($arch) { $manifest.Requirements.Architecture = $arch }
        
        $diskSpace = Read-Host "Minimum disk space (MB) [$($manifest.Requirements.MinDiskSpaceMB)]"
        if ($diskSpace) { $manifest.Requirements.MinDiskSpaceMB = [int]$diskSpace }
        
        $memory = Read-Host "Minimum memory (MB) [$($manifest.Requirements.MinMemoryMB)]"
        if ($memory) { $manifest.Requirements.MinMemoryMB = [int]$memory }
    } else {
        # Non-interactive: apply smart defaults for common installers
        if ($installerType -eq 'msi' -and -not $manifest.InstallSwitches) {
            $manifest.InstallSwitches = ""
            Write-Host "Using default MSI switches (Action1 adds /qn /norestart automatically)"
        } elseif ($installerType -eq 'exe' -and -not $manifest.InstallSwitches) {
            $manifest.InstallSwitches = "/S"
            Write-Host "Using default EXE switch: /S"
        }
    }
    
    # Update timestamps
    $manifest.LastModified = Get-Date -Format "yyyy-MM-dd"
    
    # Save manifest
    Write-ManifestFile -Manifest $manifest -Path $ManifestPath
    
    # Display summary
    Write-Host "`n=== Package Summary ===" -ForegroundColor Green
    Write-Host "Application: $($manifest.AppName) v$($manifest.Version)"
    Write-Host "Installer: $($manifest.InstallerFileName) ($installerType)"
    Write-Host "Install switches: $($manifest.InstallSwitches)"
    if ($installerType -eq 'msi') {
        Write-Host "  (Action1 will add: $script:DefaultMsiSwitches)"
    }
    Write-Host "Detection: $($manifest.DetectionMethod.Type)"
    Write-Host "`n✓ Package prepared successfully!" -ForegroundColor Green
    Write-Host "Manifest saved to: $ManifestPath" -ForegroundColor Cyan
    
    return $manifest
}

function Deploy-Action1App {
    <#
    .SYNOPSIS
        Deploys a new application to Action1.
    
    .DESCRIPTION
        Creates a new application package in Action1 based on the manifest configuration
        and uploads the installer file.
    
    .PARAMETER ManifestPath
        Path to the manifest.json file.
    
    .PARAMETER OrganizationId
        Action1 organization ID. If not specified, uses value from manifest or prompts.
    
    .PARAMETER WhatIf
        Shows what would be deployed without actually deploying.
    
    .EXAMPLE
        Deploy-Action1App -ManifestPath ".\7-Zip\manifest.json"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,
        
        [Parameter()]
        [string]$OrganizationId,
        
        [Parameter()]
        [switch]$DryRun
    )
    
    Write-Host "`n=== Action1 Application Deployment ===" -ForegroundColor Cyan
    
    # Load manifest
    $manifest = Read-ManifestFile -Path $ManifestPath
    $repoPath = Split-Path $ManifestPath -Parent
    
    # Validate installer exists
    $installerPath = Join-Path $repoPath "installers" $manifest.InstallerFileName
    if (-not (Test-Path $installerPath)) {
        throw "Installer file not found: $installerPath"
    }
    
    # Get organization ID
    if (-not $OrganizationId) {
        if ($manifest.Action1Config.OrganizationId) {
            $OrganizationId = $manifest.Action1Config.OrganizationId
        } else {
            $OrganizationId = Read-Host "Enter Action1 Organization ID"
            $manifest.Action1Config.OrganizationId = $OrganizationId
            Write-ManifestFile -Manifest $manifest -Path $ManifestPath
        }
    }
    
    if ($DryRun) {
        Write-Host "`n=== Deployment Preview (WhatIf) ===" -ForegroundColor Yellow
        Write-Host "Would deploy the following:"
        Write-Host "  App Name: $($manifest.AppName)"
        Write-Host "  Version: $($manifest.Version)"
        Write-Host "  Installer: $($manifest.InstallerFileName)"
        Write-Host "  Type: $($manifest.InstallerType)"
        Write-Host "  Switches: $($manifest.InstallSwitches)"
        Write-Host "  Organization: $OrganizationId"
        return
    }
    
    Write-Host "`nPreparing deployment..." -ForegroundColor Yellow
    
    try {
        # Step 1: Create application package
        Write-Host "Creating application package in Action1..."
        
        $packageData = @{
            name = $manifest.AppName
            version = $manifest.Version
            description = $manifest.Description
            publisher = $manifest.Publisher
            installerType = $manifest.InstallerType
            installParameters = $manifest.InstallSwitches
            uninstallParameters = $manifest.UninstallSwitches
            detectionMethod = $manifest.DetectionMethod
            requirements = $manifest.Requirements
        }
        
        $createResponse = Invoke-Action1ApiRequest `
            -Endpoint "organizations/$OrganizationId/packages" `
            -Method POST `
            -Body $packageData
        
        $packageId = $createResponse.id
        Write-Action1Log "Package created successfully: $packageId" -Level INFO
        Write-Host "✓ Package created with ID: $packageId" -ForegroundColor Green
        
        # Step 2: Upload installer file with progress
        Write-Host "Uploading installer file..."
        Write-Action1Log "Starting installer upload: $installerPath" -Level INFO
        
        $fileSize = (Get-Item $installerPath).Length
        Write-Action1Log "Installer size: $(ConvertTo-FileSize -Bytes $fileSize)" -Level DEBUG
        
        $uploadResponse = Invoke-Action1FileUpload `
            -FilePath $installerPath `
            -Endpoint "organizations/$OrganizationId/packages/$packageId/upload" `
            -ChunkSizeMB 5
        
        Write-Host "✓ Installer uploaded successfully" -ForegroundColor Green
        Write-Action1Log "Installer upload completed" -Level INFO
        
        # Step 3: Check for pre/post install scripts
        $preInstallScript = Join-Path $repoPath "scripts" "pre-install.ps1"
        $postInstallScript = Join-Path $repoPath "scripts" "post-install.ps1"
        
        if (Test-Path $preInstallScript) {
            Write-Host "Uploading pre-install script..."
            $scriptContent = Get-Content $preInstallScript -Raw
            $scriptData = @{
                type = 'pre-install'
                content = $scriptContent
            }
            Invoke-Action1ApiRequest `
                -Endpoint "organizations/$OrganizationId/packages/$packageId/scripts" `
                -Method POST `
                -Body $scriptData
            Write-Host "✓ Pre-install script uploaded" -ForegroundColor Green
        }
        
        if (Test-Path $postInstallScript) {
            Write-Host "Uploading post-install script..."
            $scriptContent = Get-Content $postInstallScript -Raw
            $scriptData = @{
                type = 'post-install'
                content = $scriptContent
            }
            Invoke-Action1ApiRequest `
                -Endpoint "organizations/$OrganizationId/packages/$packageId/scripts" `
                -Method POST `
                -Body $scriptData
            Write-Host "✓ Post-install script uploaded" -ForegroundColor Green
        }
        
        # Update manifest with package ID
        $manifest.Action1Config.PackageId = $packageId
        Write-ManifestFile -Manifest $manifest -Path $ManifestPath
        
        Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
        Write-Host "Application: $($manifest.AppName) v$($manifest.Version)"
        Write-Host "Package ID: $packageId"
        Write-Host "Status: Ready for deployment"
        Write-Host "`nNext steps:"
        Write-Host "1. Create a deployment policy in Action1 console"
        Write-Host "2. Assign the package to target endpoints"
        Write-Host "3. Monitor deployment status"
        
        return @{
            Success = $true
            PackageId = $packageId
            AppName = $manifest.AppName
            Version = $manifest.Version
        }
    }
    catch {
        Write-Error "Deployment failed: $($_.Exception.Message)"
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Deploy-Action1AppUpdate {
    <#
    .SYNOPSIS
        Deploys an update to an existing Action1 application.
    
    .DESCRIPTION
        Updates an existing application package in Action1 with a new version.
    
    .PARAMETER ManifestPath
        Path to the manifest.json file.
    
    .PARAMETER Force
        Forces the update even if version hasn't changed.
    
    .EXAMPLE
        Deploy-Action1AppUpdate -ManifestPath ".\7-Zip\manifest.json"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,
        
        [Parameter()]
        [switch]$Force
    )
    
    Write-Host "`n=== Action1 Application Update ===" -ForegroundColor Cyan
    
    # Load manifest
    $manifest = Read-ManifestFile -Path $ManifestPath
    
    if (-not $manifest.Action1Config.PackageId) {
        Write-Error "No existing package found in manifest. Use Deploy-Action1App for initial deployment."
        return
    }
    
    $packageId = $manifest.Action1Config.PackageId
    $orgId = $manifest.Action1Config.OrganizationId
    $repoPath = Split-Path $ManifestPath -Parent
    
    Write-Host "Updating package: $packageId"
    Write-Host "New version: $($manifest.Version)"
    
    if ($PSCmdlet.ShouldProcess($manifest.AppName, "Update application")) {
        try {
            # Update package metadata
            Write-Host "Updating package metadata..."
            
            $updateData = @{
                version = $manifest.Version
                description = $manifest.Description
                installParameters = $manifest.InstallSwitches
                uninstallParameters = $manifest.UninstallSwitches
                lastModified = Get-Date -Format "o"
            }
            
            Invoke-Action1ApiRequest `
                -Endpoint "organizations/$orgId/packages/$packageId" `
                -Method PATCH `
                -Body $updateData
            
            Write-Host "✓ Package metadata updated" -ForegroundColor Green
            
            # Upload new installer if changed
            $installerPath = Join-Path $repoPath "installers" $manifest.InstallerFileName
            if (Test-Path $installerPath) {
                $uploadNew = Read-Host "Upload new installer file? (y/N)"
                if ($uploadNew -eq 'y' -or $uploadNew -eq 'Y') {
                    Write-Host "Uploading updated installer..."
                    Write-Action1Log "Starting installer update upload" -Level INFO
                    
                    $fileSize = (Get-Item $installerPath).Length
                    Write-Action1Log "Installer size: $(ConvertTo-FileSize -Bytes $fileSize)" -Level DEBUG
                    
                    # Use progress-enabled upload
                    Invoke-Action1FileUpload `
                        -FilePath $installerPath `
                        -Endpoint "organizations/$orgId/packages/$packageId/upload" `
                        -ChunkSizeMB 5
                    
                    Write-Host "✓ Installer updated" -ForegroundColor Green
                    Write-Action1Log "Installer update completed" -Level INFO
                }
            }
            
            Write-Host "`n✓ Update completed successfully!" -ForegroundColor Green
            
            return @{
                Success = $true
                PackageId = $packageId
                Version = $manifest.Version
            }
        }
        catch {
            Write-Error "Update failed: $($_.Exception.Message)"
            return @{
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
}

function Get-Action1App {
    <#
    .SYNOPSIS
        Retrieves information about Action1 applications with interactive drill-down.

    .DESCRIPTION
        Lists applications or gets details about a specific application from Action1.
        If no OrganizationId is provided, prompts user to select from available organizations,
        then allows drilling down into repos, apps, and versions.

    .PARAMETER OrganizationId
        Action1 organization ID. If not specified, prompts user to select.

    .PARAMETER PackageId
        Specific package/repo ID to retrieve.

    .PARAMETER VersionId
        Specific version ID to retrieve (requires PackageId).

    .PARAMETER Name
        Filter by application name.

    .PARAMETER NoInteractive
        Disable interactive drill-down mode. By default, when no parameters are provided,
        interactive mode is enabled to browse repos → versions.

    .EXAMPLE
        Get-Action1App
        # Full interactive drill-down through org → repo → version

    .EXAMPLE
        Get-Action1App -NoInteractive
        # Returns repos list without drill-down prompts

    .EXAMPLE
        Get-Action1App -OrganizationId "org123" -Name "7-Zip"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$PackageId,

        [Parameter()]
        [string]$VersionId,

        [Parameter()]
        [string]$Name,

        [Parameter()]
        [switch]$NoInteractive
    )

    try {
        # If no OrganizationId provided, fetch and prompt for selection
        if (-not $OrganizationId) {
            Write-Action1Log "Fetching available organizations..." -Level INFO
            $orgsResponse = Invoke-Action1ApiRequest -Endpoint "organizations" -Method GET

            $orgs = if ($orgsResponse.items) { $orgsResponse.items } else { @($orgsResponse) }

            if ($orgs.Count -eq 0) {
                throw "No organizations found."
            }

            if ($orgs.Count -eq 1) {
                # Still offer "All" option even with single org
                Write-Host "`nSelect Organization:" -ForegroundColor Cyan
                Write-Host "  [1] All (Enterprise-wide)"
                Write-Host "  [2] $($orgs[0].name)"

                $selection = Read-Host "`nEnter selection (1-2)"
                if ($selection -eq '1') {
                    $OrganizationId = 'all'
                    Write-Host "Selected: All (Enterprise-wide)" -ForegroundColor Green
                }
                else {
                    $OrganizationId = $orgs[0].id
                    Write-Host "Selected: $($orgs[0].name)" -ForegroundColor Green
                }
            }
            else {
                Write-Host "`nSelect Organization:" -ForegroundColor Cyan
                Write-Host "  [1] All (Enterprise-wide)"
                for ($i = 0; $i -lt $orgs.Count; $i++) {
                    Write-Host "  [$($i + 2)] $($orgs[$i].name)"
                }

                $maxSelection = $orgs.Count + 1
                $selection = Read-Host "`nEnter selection (1-$maxSelection)"
                $selNum = [int]$selection

                if ($selNum -eq 1) {
                    $OrganizationId = 'all'
                    Write-Host "Selected: All (Enterprise-wide)" -ForegroundColor Green
                }
                elseif ($selNum -ge 2 -and $selNum -le $maxSelection) {
                    $selIndex = $selNum - 2
                    $OrganizationId = $orgs[$selIndex].id
                    Write-Host "Selected: $($orgs[$selIndex].name)" -ForegroundColor Green
                }
                else {
                    throw "Invalid selection."
                }
            }
        }

        # If specific version requested
        if ($PackageId -and $VersionId) {
            $version = Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId/$PackageId/versions/$VersionId" `
                -Method GET
            return $version
        }

        # If specific package requested (list versions)
        if ($PackageId) {
            $response = Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId/$PackageId/versions?limit=100" `
                -Method GET

            $versions = if ($response.items) { $response.items } elseif ($response.type -eq 'Version') { @($response) } else { @() }
            return $versions
        }

        # Get repos list
        $response = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId`?custom=yes&builtin=no&limit=100" `
            -Method GET

        $repos = if ($response.items) { $response.items } else { @($response) }

        if ($Name) {
            $repos = $repos | Where-Object { $_.name -like "*$Name*" }
        }

        # If NoInteractive flag set, just return the repos
        if ($NoInteractive) {
            return $repos
        }

        # Interactive mode - drill down through repos → versions
        if ($repos.Count -eq 0) {
            Write-Host "`nNo repositories found." -ForegroundColor Yellow
            return @()
        }

        # Select a repo
        Write-Host "`nSelect Repository:" -ForegroundColor Cyan
        Write-Host "  [0] Return all repositories (no drill-down)"
        for ($i = 0; $i -lt $repos.Count; $i++) {
            $repo = $repos[$i]
            $platform = if ($repo.platform) { " [$($repo.platform)]" } else { "" }
            Write-Host "  [$($i + 1)] $($repo.name)$platform - $($repo.vendor)"
        }

        $repoSelection = Read-Host "`nEnter selection (0-$($repos.Count))"
        $repoNum = [int]$repoSelection

        if ($repoNum -eq 0) {
            return $repos
        }

        if ($repoNum -lt 1 -or $repoNum -gt $repos.Count) {
            throw "Invalid selection."
        }

        $selectedRepo = $repos[$repoNum - 1]
        Write-Host "Selected repo: $($selectedRepo.name)" -ForegroundColor Green

        # Fetch versions for selected repo
        Write-Action1Log "Fetching versions for $($selectedRepo.name)..." -Level INFO
        $versionsResponse = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId/$($selectedRepo.id)/versions?limit=100" `
            -Method GET

        $versions = if ($versionsResponse.items) {
            $versionsResponse.items
        } elseif ($versionsResponse.type -eq 'Version') {
            @($versionsResponse)
        } else {
            @()
        }

        if ($versions.Count -eq 0) {
            Write-Host "`nNo versions found for this repository." -ForegroundColor Yellow
            return $selectedRepo
        }

        # Select a version
        Write-Host "`nSelect Version:" -ForegroundColor Cyan
        Write-Host "  [0] Return all versions (no drill-down)"
        for ($i = 0; $i -lt $versions.Count; $i++) {
            $ver = $versions[$i]
            $status = if ($ver.status) { " ($($ver.status))" } else { "" }
            $date = if ($ver.release_date) { " - $($ver.release_date)" } else { "" }
            Write-Host "  [$($i + 1)] v$($ver.version)$status$date"
        }

        $verSelection = Read-Host "`nEnter selection (0-$($versions.Count))"
        $verNum = [int]$verSelection

        if ($verNum -eq 0) {
            return $versions
        }

        if ($verNum -lt 1 -or $verNum -gt $versions.Count) {
            throw "Invalid selection."
        }

        $selectedVersion = $versions[$verNum - 1]
        Write-Host "Selected version: v$($selectedVersion.version)" -ForegroundColor Green

        # Fetch full version details
        Write-Action1Log "Fetching version details..." -Level INFO
        $versionDetails = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId/$($selectedRepo.id)/versions/$($selectedVersion.id)" `
            -Method GET

        return $versionDetails
    }
    catch {
        Write-Error "Failed to retrieve applications: $($_.Exception.Message)"
    }
}

function Get-Action1Organization {
    <#
    .SYNOPSIS
        Retrieves organizations from Action1.

    .DESCRIPTION
        Lists all organizations the authenticated user has access to.

    .EXAMPLE
        Get-Action1Organization
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Action1Log "Fetching organizations..." -Level INFO
        $response = Invoke-Action1ApiRequest -Endpoint "organizations" -Method GET
        $orgs = if ($response.items) { $response.items } else { @($response) }
        return $orgs
    }
    catch {
        Write-Error "Failed to retrieve organizations: $($_.Exception.Message)"
    }
}

function Get-Action1EndpointGroup {
    <#
    .SYNOPSIS
        Retrieves endpoint groups from Action1.

    .DESCRIPTION
        Lists endpoint groups for an organization. If no OrganizationId is provided,
        prompts user to select from available organizations.

    .PARAMETER OrganizationId
        Action1 organization ID. If not specified, prompts user to select.

    .PARAMETER GroupId
        Specific group ID to retrieve details for.

    .PARAMETER Name
        Filter groups by name.

    .EXAMPLE
        Get-Action1EndpointGroup
        # Interactive selection of organization then lists groups

    .EXAMPLE
        Get-Action1EndpointGroup -OrganizationId "org123" -Name "Servers"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$GroupId,

        [Parameter()]
        [string]$Name
    )

    try {
        # If no OrganizationId provided, prompt for selection
        if (-not $OrganizationId) {
            $orgs = Get-Action1Organization
            if ($orgs.Count -eq 0) {
                throw "No organizations found."
            }

            Write-Host "`nSelect Organization:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $orgs.Count; $i++) {
                Write-Host "  [$($i + 1)] $($orgs[$i].name)"
            }

            $selection = Read-Host "`nEnter selection (1-$($orgs.Count))"
            $selNum = [int]$selection

            if ($selNum -lt 1 -or $selNum -gt $orgs.Count) {
                throw "Invalid selection."
            }

            $OrganizationId = $orgs[$selNum - 1].id
            Write-Host "Selected: $($orgs[$selNum - 1].name)" -ForegroundColor Green
        }

        # If specific group requested
        if ($GroupId) {
            $group = Invoke-Action1ApiRequest `
                -Endpoint "organizations/$OrganizationId/endpoint_groups/$GroupId" `
                -Method GET
            return $group
        }

        # List all groups
        Write-Action1Log "Fetching endpoint groups for organization $OrganizationId..." -Level INFO
        $response = Invoke-Action1ApiRequest `
            -Endpoint "organizations/$OrganizationId/endpoint_groups?limit=100" `
            -Method GET

        $groups = if ($response.items) { $response.items } else { @($response) }

        if ($Name) {
            $groups = $groups | Where-Object { $_.name -like "*$Name*" }
        }

        return $groups
    }
    catch {
        Write-Error "Failed to retrieve endpoint groups: $($_.Exception.Message)"
    }
}

function New-Action1EndpointGroup {
    <#
    .SYNOPSIS
        Creates a new endpoint group in Action1.

    .DESCRIPTION
        Creates an endpoint group with the specified configuration.

    .PARAMETER OrganizationId
        Action1 organization ID.

    .PARAMETER Name
        Name of the endpoint group.

    .PARAMETER Description
        Description of the endpoint group.

    .PARAMETER Filter
        Dynamic filter criteria for the group (optional).

    .EXAMPLE
        New-Action1EndpointGroup -OrganizationId "org123" -Name "Windows Servers" -Description "All Windows Server endpoints"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationId,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Description = "",

        [Parameter()]
        [hashtable]$Filter
    )

    try {
        Write-Action1Log "Creating endpoint group: $Name" -Level INFO

        $groupData = @{
            name = $Name
            description = $Description
        }

        if ($Filter) {
            $groupData['filter'] = $Filter
        }

        $response = Invoke-Action1ApiRequest `
            -Endpoint "organizations/$OrganizationId/endpoint_groups" `
            -Method POST `
            -Body $groupData

        Write-Host "Endpoint group created: $($response.name) (ID: $($response.id))" -ForegroundColor Green
        return $response
    }
    catch {
        Write-Error "Failed to create endpoint group: $($_.Exception.Message)"
    }
}

function Get-Action1Automation {
    <#
    .SYNOPSIS
        Retrieves automations (policies) from Action1.

    .DESCRIPTION
        Lists automations for an organization with interactive drill-down.
        If no OrganizationId is provided, prompts user to select from available organizations.

    .PARAMETER OrganizationId
        Action1 organization ID. If not specified, prompts user to select.

    .PARAMETER AutomationId
        Specific automation ID to retrieve details for.

    .PARAMETER Name
        Filter automations by name.

    .PARAMETER NoInteractive
        Disable interactive mode. By default, allows selecting an automation for details.

    .EXAMPLE
        Get-Action1Automation
        # Interactive selection of organization and automation

    .EXAMPLE
        Get-Action1Automation -OrganizationId "org123" -NoInteractive
        # Returns all automations without prompts
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$AutomationId,

        [Parameter()]
        [string]$Name,

        [Parameter()]
        [switch]$NoInteractive
    )

    try {
        # If no OrganizationId provided, prompt for selection
        if (-not $OrganizationId) {
            $orgs = Get-Action1Organization
            if ($orgs.Count -eq 0) {
                throw "No organizations found."
            }

            Write-Host "`nSelect Organization:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $orgs.Count; $i++) {
                Write-Host "  [$($i + 1)] $($orgs[$i].name)"
            }

            $selection = Read-Host "`nEnter selection (1-$($orgs.Count))"
            $selNum = [int]$selection

            if ($selNum -lt 1 -or $selNum -gt $orgs.Count) {
                throw "Invalid selection."
            }

            $OrganizationId = $orgs[$selNum - 1].id
            Write-Host "Selected: $($orgs[$selNum - 1].name)" -ForegroundColor Green
        }

        # If specific automation requested
        if ($AutomationId) {
            Write-Action1Log "Fetching automation details: $AutomationId" -Level INFO
            $automation = Invoke-Action1ApiRequest `
                -Endpoint "organizations/$OrganizationId/automations/$AutomationId" `
                -Method GET
            return $automation
        }

        # List all automations
        Write-Action1Log "Fetching automations for organization $OrganizationId..." -Level INFO
        $response = Invoke-Action1ApiRequest `
            -Endpoint "organizations/$OrganizationId/automations?limit=100" `
            -Method GET

        $automations = if ($response.items) { $response.items } else { @($response) }

        if ($Name) {
            $automations = $automations | Where-Object { $_.name -like "*$Name*" }
        }

        # If NoInteractive, just return the list
        if ($NoInteractive) {
            return $automations
        }

        # Interactive mode - allow selecting an automation for details
        if ($automations.Count -eq 0) {
            Write-Host "`nNo automations found." -ForegroundColor Yellow
            return @()
        }

        Write-Host "`nSelect Automation:" -ForegroundColor Cyan
        Write-Host "  [0] Return all automations (no drill-down)"
        for ($i = 0; $i -lt $automations.Count; $i++) {
            $auto = $automations[$i]
            $status = if ($auto.enabled) { "[Enabled]" } else { "[Disabled]" }
            $trigger = if ($auto.trigger_type) { "($($auto.trigger_type))" } else { "" }
            Write-Host "  [$($i + 1)] $($auto.name) $status $trigger"
        }

        $autoSelection = Read-Host "`nEnter selection (0-$($automations.Count))"
        $autoNum = [int]$autoSelection

        if ($autoNum -eq 0) {
            return $automations
        }

        if ($autoNum -lt 1 -or $autoNum -gt $automations.Count) {
            throw "Invalid selection."
        }

        $selectedAutomation = $automations[$autoNum - 1]
        Write-Host "Selected: $($selectedAutomation.name)" -ForegroundColor Green

        # Fetch full automation details
        Write-Action1Log "Fetching automation details..." -Level INFO
        $automationDetails = Invoke-Action1ApiRequest `
            -Endpoint "organizations/$OrganizationId/automations/$($selectedAutomation.id)" `
            -Method GET

        return $automationDetails
    }
    catch {
        Write-Error "Failed to retrieve automations: $($_.Exception.Message)"
    }
}

function Copy-Action1Automation {
    <#
    .SYNOPSIS
        Copies automations between Action1 organizations.

    .DESCRIPTION
        Clones one or more automations from a source organization to one or more
        destination organizations. If endpoint groups referenced by the automation
        don't exist in the destination, they will be created.

    .PARAMETER SourceOrgId
        Source organization ID. If not specified, prompts for selection.

    .PARAMETER DestinationOrgIds
        Array of destination organization IDs. If not specified, prompts for selection.

    .PARAMETER AutomationIds
        Array of automation IDs to copy. If not specified, prompts for selection.

    .PARAMETER IncludeGroups
        If specified, copies referenced endpoint groups to destinations (default: $true).

    .EXAMPLE
        Copy-Action1Automation
        # Fully interactive - prompts for source org, automations, and destinations

    .EXAMPLE
        Copy-Action1Automation -SourceOrgId "org1" -DestinationOrgIds @("org2", "org3") -AutomationIds @("auto1")
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SourceOrgId,

        [Parameter()]
        [string[]]$DestinationOrgIds,

        [Parameter()]
        [string[]]$AutomationIds,

        [Parameter()]
        [bool]$IncludeGroups = $true
    )

    try {
        # Get all organizations first
        $orgs = Get-Action1Organization
        if ($orgs.Count -lt 2) {
            throw "At least 2 organizations are required to copy automations between them."
        }

        # Select source organization
        if (-not $SourceOrgId) {
            Write-Host "`n=== Select SOURCE Organization ===" -ForegroundColor Cyan
            for ($i = 0; $i -lt $orgs.Count; $i++) {
                Write-Host "  [$($i + 1)] $($orgs[$i].name)"
            }

            $selection = Read-Host "`nEnter selection (1-$($orgs.Count))"
            $selNum = [int]$selection

            if ($selNum -lt 1 -or $selNum -gt $orgs.Count) {
                throw "Invalid selection."
            }

            $SourceOrgId = $orgs[$selNum - 1].id
            $sourceOrgName = $orgs[$selNum - 1].name
            Write-Host "Source: $sourceOrgName" -ForegroundColor Green
        }
        else {
            $sourceOrgName = ($orgs | Where-Object { $_.id -eq $SourceOrgId }).name
        }

        # Get automations from source
        Write-Action1Log "Fetching automations from source organization..." -Level INFO
        $automations = Get-Action1Automation -OrganizationId $SourceOrgId -NoInteractive

        if ($automations.Count -eq 0) {
            Write-Host "No automations found in source organization." -ForegroundColor Yellow
            return
        }

        # Select automations to copy
        if (-not $AutomationIds) {
            Write-Host "`n=== Select Automations to Copy ===" -ForegroundColor Cyan
            Write-Host "  [0] Select ALL automations"
            for ($i = 0; $i -lt $automations.Count; $i++) {
                $auto = $automations[$i]
                $status = if ($auto.enabled) { "[Enabled]" } else { "[Disabled]" }
                Write-Host "  [$($i + 1)] $($auto.name) $status"
            }

            $autoInput = Read-Host "`nEnter selection(s) - comma-separated for multiple (e.g., 1,3,5) or 0 for all"

            if ($autoInput -eq '0') {
                $AutomationIds = $automations | ForEach-Object { $_.id }
                Write-Host "Selected: ALL automations ($($AutomationIds.Count) total)" -ForegroundColor Green
            }
            else {
                $selections = $autoInput -split ',' | ForEach-Object { [int]$_.Trim() }
                $AutomationIds = @()
                foreach ($sel in $selections) {
                    if ($sel -ge 1 -and $sel -le $automations.Count) {
                        $AutomationIds += $automations[$sel - 1].id
                    }
                }
                Write-Host "Selected: $($AutomationIds.Count) automation(s)" -ForegroundColor Green
            }
        }

        # Select destination organizations
        if (-not $DestinationOrgIds) {
            Write-Host "`n=== Select DESTINATION Organization(s) ===" -ForegroundColor Cyan
            Write-Host "  [0] Select ALL other organizations"
            $otherOrgs = $orgs | Where-Object { $_.id -ne $SourceOrgId }
            for ($i = 0; $i -lt $otherOrgs.Count; $i++) {
                Write-Host "  [$($i + 1)] $($otherOrgs[$i].name)"
            }

            $destInput = Read-Host "`nEnter selection(s) - comma-separated for multiple (e.g., 1,3) or 0 for all"

            if ($destInput -eq '0') {
                $DestinationOrgIds = $otherOrgs | ForEach-Object { $_.id }
                Write-Host "Selected: ALL other organizations ($($DestinationOrgIds.Count) total)" -ForegroundColor Green
            }
            else {
                $selections = $destInput -split ',' | ForEach-Object { [int]$_.Trim() }
                $DestinationOrgIds = @()
                foreach ($sel in $selections) {
                    if ($sel -ge 1 -and $sel -le $otherOrgs.Count) {
                        $DestinationOrgIds += $otherOrgs[$sel - 1].id
                    }
                }
                Write-Host "Selected: $($DestinationOrgIds.Count) destination(s)" -ForegroundColor Green
            }
        }

        # Confirm the operation
        Write-Host "`n=== Copy Summary ===" -ForegroundColor Yellow
        Write-Host "Source: $sourceOrgName"
        Write-Host "Automations: $($AutomationIds.Count)"
        Write-Host "Destinations: $($DestinationOrgIds.Count) organization(s)"
        Write-Host "Include Groups: $IncludeGroups"

        $confirm = Read-Host "`nProceed with copy? (Y/n)"
        if ($confirm -eq 'n' -or $confirm -eq 'N') {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            return
        }

        # Process each automation
        $results = @()
        $totalOperations = $AutomationIds.Count * $DestinationOrgIds.Count
        $currentOp = 0

        foreach ($autoId in $AutomationIds) {
            # Get full automation details
            Write-Action1Log "Fetching automation details: $autoId" -Level INFO
            $automation = Get-Action1Automation -OrganizationId $SourceOrgId -AutomationId $autoId

            Write-Host "`nProcessing: $($automation.name)" -ForegroundColor Cyan

            # Get referenced endpoint groups from the automation
            $referencedGroupIds = @()
            if ($automation.endpoint_group_id) {
                $referencedGroupIds += $automation.endpoint_group_id
            }
            if ($automation.endpoint_groups) {
                $referencedGroupIds += $automation.endpoint_groups | ForEach-Object { $_.id }
            }

            # Get group details from source if we need to copy them
            $sourceGroups = @{}
            if ($IncludeGroups -and $referencedGroupIds.Count -gt 0) {
                foreach ($groupId in $referencedGroupIds) {
                    try {
                        $group = Get-Action1EndpointGroup -OrganizationId $SourceOrgId -GroupId $groupId
                        $sourceGroups[$groupId] = $group
                        Write-Action1Log "Found referenced group: $($group.name)" -Level DEBUG
                    }
                    catch {
                        Write-Action1Log "Could not fetch group $groupId" -Level WARN
                    }
                }
            }

            # Copy to each destination
            foreach ($destOrgId in $DestinationOrgIds) {
                $currentOp++
                $destOrgName = ($orgs | Where-Object { $_.id -eq $destOrgId }).name
                $percentComplete = [int](($currentOp / $totalOperations) * 100)

                Write-Progress -Activity "Copying Automations" -Status "Copying '$($automation.name)' to $destOrgName" -PercentComplete $percentComplete

                Write-Host "  -> $destOrgName" -ForegroundColor Gray

                try {
                    # Map group IDs - check if groups exist in destination, create if not
                    $groupIdMapping = @{}
                    if ($IncludeGroups -and $sourceGroups.Count -gt 0) {
                        # Get existing groups in destination
                        $destGroups = Get-Action1EndpointGroup -OrganizationId $destOrgId

                        foreach ($srcGroupId in $sourceGroups.Keys) {
                            $srcGroup = $sourceGroups[$srcGroupId]

                            # Check if group with same name exists
                            $existingGroup = $destGroups | Where-Object { $_.name -eq $srcGroup.name } | Select-Object -First 1

                            if ($existingGroup) {
                                Write-Action1Log "Group '$($srcGroup.name)' already exists in destination" -Level DEBUG
                                $groupIdMapping[$srcGroupId] = $existingGroup.id
                            }
                            else {
                                # Create the group in destination
                                Write-Host "    Creating group: $($srcGroup.name)" -ForegroundColor DarkGray
                                $newGroup = New-Action1EndpointGroup `
                                    -OrganizationId $destOrgId `
                                    -Name $srcGroup.name `
                                    -Description $srcGroup.description

                                $groupIdMapping[$srcGroupId] = $newGroup.id
                            }
                        }
                    }

                    # Prepare automation data for creation
                    $newAutomationData = @{
                        name = $automation.name
                        description = if ($automation.description) { $automation.description } else { "" }
                        enabled = $automation.enabled
                    }

                    # Copy relevant properties
                    if ($automation.trigger_type) {
                        $newAutomationData['trigger_type'] = $automation.trigger_type
                    }
                    if ($automation.trigger) {
                        $newAutomationData['trigger'] = $automation.trigger
                    }
                    if ($automation.actions) {
                        $newAutomationData['actions'] = $automation.actions
                    }
                    if ($automation.schedule) {
                        $newAutomationData['schedule'] = $automation.schedule
                    }

                    # Update endpoint group references with mapped IDs
                    if ($automation.endpoint_group_id -and $groupIdMapping.ContainsKey($automation.endpoint_group_id)) {
                        $newAutomationData['endpoint_group_id'] = $groupIdMapping[$automation.endpoint_group_id]
                    }
                    elseif ($automation.endpoint_group_id) {
                        $newAutomationData['endpoint_group_id'] = $automation.endpoint_group_id
                    }

                    # Create the automation in destination
                    Write-Action1Log "Creating automation in destination..." -Level DEBUG
                    $response = Invoke-Action1ApiRequest `
                        -Endpoint "organizations/$destOrgId/automations" `
                        -Method POST `
                        -Body $newAutomationData

                    Write-Host "    Created: $($response.id)" -ForegroundColor Green

                    $results += @{
                        SourceAutomation = $automation.name
                        SourceAutomationId = $autoId
                        DestinationOrg = $destOrgName
                        DestinationOrgId = $destOrgId
                        NewAutomationId = $response.id
                        Status = 'Success'
                        GroupsCopied = $groupIdMapping.Count
                    }
                }
                catch {
                    Write-Host "    Failed: $($_.Exception.Message)" -ForegroundColor Red
                    $results += @{
                        SourceAutomation = $automation.name
                        SourceAutomationId = $autoId
                        DestinationOrg = $destOrgName
                        DestinationOrgId = $destOrgId
                        NewAutomationId = $null
                        Status = 'Failed'
                        Error = $_.Exception.Message
                    }
                }
            }
        }

        Write-Progress -Activity "Copying Automations" -Completed

        # Summary
        Write-Host "`n=== Copy Results ===" -ForegroundColor Green
        $successCount = ($results | Where-Object { $_.Status -eq 'Success' }).Count
        $failCount = ($results | Where-Object { $_.Status -eq 'Failed' }).Count

        Write-Host "Successful: $successCount" -ForegroundColor Green
        if ($failCount -gt 0) {
            Write-Host "Failed: $failCount" -ForegroundColor Red
        }

        return $results
    }
    catch {
        Write-Error "Failed to copy automations: $($_.Exception.Message)"
    }
}

function Remove-Action1App {
    <#
    .SYNOPSIS
        Removes an application from Action1.
    
    .DESCRIPTION
        Deletes an application package from Action1.
    
    .PARAMETER OrganizationId
        Action1 organization ID.
    
    .PARAMETER PackageId
        Package ID to remove.
    
    .PARAMETER Force
        Skips confirmation prompt.
    
    .EXAMPLE
        Remove-Action1App -OrganizationId "org123" -PackageId "pkg456"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationId,
        
        [Parameter(Mandatory)]
        [string]$PackageId,
        
        [Parameter()]
        [switch]$Force
    )
    
    if ($Force -or $PSCmdlet.ShouldProcess($PackageId, "Remove application package")) {
        try {
            Invoke-Action1ApiRequest `
                -Endpoint "organizations/$OrganizationId/packages/$PackageId" `
                -Method DELETE
            
            Write-Host "✓ Application package removed successfully" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to remove application: $($_.Exception.Message)"
        }
    }
}

#endregion

# Module initialization
Write-Verbose "Action1AppDeployment module loaded"

# Try to load saved credentials if they exist
$credPath = if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
    "$env:LOCALAPPDATA\Action1AppDeployment\credentials.json"
} else {
    "$HOME/.action1/credentials.json"
}

if (Test-Path $credPath) {
    try {
        $savedCreds = Get-Content $credPath -Raw | ConvertFrom-Json

        # Support both old (ApiKey/Secret) and new (ClientId/ClientSecret) formats
        if ($savedCreds.ClientId) {
            $script:Action1ClientId = $savedCreds.ClientId
            $script:Action1ClientSecret = $savedCreds.ClientSecret
            $script:Action1Region = $savedCreds.Region ?? 'NorthAmerica'
        } elseif ($savedCreds.ApiKey) {
            # Legacy format support
            $script:Action1ClientId = $savedCreds.ApiKey
            $script:Action1ClientSecret = $savedCreds.Secret
            $script:Action1Region = 'NorthAmerica'
        }

        # Set the base URI based on region
        if ($script:Action1Region -and $script:Action1RegionUrls.ContainsKey($script:Action1Region)) {
            $script:Action1BaseUri = $script:Action1RegionUrls[$script:Action1Region]
        }

        Write-Verbose "Loaded saved Action1 credentials (Region: $($script:Action1Region))"
    }
    catch {
        Write-Verbose "Could not load saved credentials"
    }
}

Export-ModuleMember -Function @(
    'Deploy-Action1App',
    'Deploy-Action1AppUpdate',
    'New-Action1AppRepo',
    'New-Action1AppPackage',
    'Get-Action1App',
    'Remove-Action1App',
    'Test-Action1Connection',
    'Set-Action1ApiCredentials',
    'Set-Action1LogLevel',
    'Get-Action1LogLevel',
    'Get-Action1Organization',
    'Get-Action1EndpointGroup',
    'New-Action1EndpointGroup',
    'Get-Action1Automation',
    'Copy-Action1Automation'
)
