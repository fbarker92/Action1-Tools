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
$script:LogLevel = "SILENT"
$script:LogFilePath = $null

# Cross-platform configuration directory path
$script:Action1ConfigDir = if ($IsWindows) {
    Join-Path $env:LOCALAPPDATA "Action1.Tools"
} elseif ($IsMacOS) {
    Join-Path $HOME ".action1"
} else {
    # Linux - follow XDG spec
    $xdgConfig = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME ".config" }
    Join-Path $xdgConfig "action1"
}
$script:LogLevels = @{
    TRACE = 0
    DEBUG = 1
    INFO = 2
    WARN = 3
    ERROR = 4
    SILENT = 5
}

#region Logging Functions

function Write-Action1Log {
    <#
    .SYNOPSIS
        Internal logging function for the module.

    .DESCRIPTION
        Provides structured logging with levels: TRACE, DEBUG, INFO, WARN, ERROR, SILENT.
        File logging is one level more verbose than console output:
        - SILENT console → INFO to file
        - ERROR console → WARN to file
        - WARN console → INFO to file
        - INFO console → DEBUG to file
        - DEBUG/TRACE console → TRACE to file
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
    
    # Determine file log level (one level more verbose than console)
    $fileLogLevel = switch ($script:LogLevel) {
        'SILENT' { 'INFO' }
        'ERROR'  { 'WARN' }
        'WARN'   { 'INFO' }
        'INFO'   { 'DEBUG' }
        'DEBUG'  { 'TRACE' }
        'TRACE'  { 'TRACE' }
    }

    # Check if this message should be shown on console or written to file
    $shouldDisplayConsole = $script:LogLevels[$Level] -ge $script:LogLevels[$script:LogLevel]
    $shouldWriteToFile = $script:LogLevels[$Level] -ge $script:LogLevels[$fileLogLevel]
    $isSilent = $script:LogLevel -eq 'SILENT'

    # Skip entirely if below both thresholds
    if (-not $shouldDisplayConsole -and -not $shouldWriteToFile) {
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $callerInfo = (Get-PSCallStack)[1]
    $caller = "$($callerInfo.Command)"

    # Build log message
    $logMessage = "[$timestamp] [$Level] [$caller] $Message"

    # Only write to console if not in SILENT mode
    if (-not $isSilent) {
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
    }

    # Add data if provided
    if ($Data) {
        $dataString = $Data | ConvertTo-Json -Depth 5 -Compress
        $dataMessage = "[$timestamp] [$Level] [$caller] DATA: $dataString"
        if (-not $isSilent) {
            Write-Host $dataMessage -ForegroundColor DarkGray
        }
        $logMessage += "`n$dataMessage"
    }

    # Add error details if provided
    if ($ErrorRecord) {
        $errorMessage = "[$timestamp] [$Level] [$caller] ERROR DETAILS: $($ErrorRecord.Exception.Message)"
        $errorMessage += "`n  at $($ErrorRecord.InvocationInfo.ScriptName):$($ErrorRecord.InvocationInfo.ScriptLineNumber)"
        if ($ErrorRecord.Exception.StackTrace) {
            $errorMessage += "`n  StackTrace: $($ErrorRecord.Exception.StackTrace)"
        }
        if (-not $isSilent) {
            Write-Host $errorMessage -ForegroundColor Red
        }
        $logMessage += "`n$errorMessage"
    }

    # Write to log file if configured and message meets file threshold
    if ($script:LogFilePath -and $shouldWriteToFile) {
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
        TRACE (most verbose) > DEBUG > INFO > WARN > ERROR > SILENT (no console output)

        File logging is automatically one level more verbose than console:
        - SILENT → logs INFO and above to file
        - ERROR → logs WARN and above to file
        - WARN → logs INFO and above to file
        - INFO → logs DEBUG and above to file
        - DEBUG/TRACE → logs TRACE and above to file

    .PARAMETER Level
        The minimum log level to display on console. Default is SILENT.

    .PARAMETER LogFile
        Optional path to write logs to a file.

    .EXAMPLE
        Set-Action1LogLevel -Level DEBUG

    .EXAMPLE
        Set-Action1LogLevel -Level TRACE -LogFile "C:\Logs\action1-deployment.log"

    .EXAMPLE
        Set-Action1LogLevel -Level SILENT -LogFile "C:\Logs\action1.log"
        # Suppresses console output but logs INFO and above to file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'SILENT')]
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

    # TRACE logging for token request (mask sensitive data)
    Write-Action1Log "Token request URL: $tokenUrl" -Level TRACE
    Write-Action1Log "Token request body" -Level TRACE -Data @{
        client_id     = $script:Action1ClientId
        client_secret = "***MASKED***"
    }

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body ($body | ConvertTo-Json) -ContentType 'application/json' -ErrorAction Stop
        $stopwatch.Stop()

        Write-Action1Log "Token request completed in $($stopwatch.ElapsedMilliseconds)ms" -Level TRACE
        Write-Action1Log "Token response" -Level TRACE -Data @{
            access_token = "***MASKED*** (length: $($response.access_token.Length))"
            expires_in   = $response.expires_in
            token_type   = $response.token_type
        }

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

    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }

    # TRACE logging for headers (mask sensitive data)
    Write-Action1Log "Request headers" -Level TRACE -Data @{
        'Authorization' = "Bearer ***MASKED*** (length: $($token.Length))"
        'Content-Type'  = $headers['Content-Type']
        'Accept'        = $headers['Accept']
    }

    Write-Action1Log "Authentication headers generated successfully" -Level DEBUG

    return $headers
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

    # TRACE: Log complete request details
    Write-Action1Log "Request endpoint: $Endpoint" -Level TRACE
    Write-Action1Log "Request full URI: $uri" -Level TRACE
    Write-Action1Log "Request method: $Method" -Level TRACE
    if ($QueryParameters) {
        Write-Action1Log "Query parameters" -Level TRACE -Data $QueryParameters
    }

    $params = @{
        Uri = $uri
        Method = $Method
        Headers = $headers
        ErrorAction = 'Stop'
    }

    $bodyJson = $null
    if ($Body) {
        $bodyJson = ($Body | ConvertTo-Json -Depth 10)
        $params['Body'] = $bodyJson
        Write-Action1Log "Request body (raw JSON)" -Level TRACE
        Write-Action1Log $bodyJson -Level TRACE
        Write-Action1Log "Request body (parsed)" -Level TRACE -Data $Body
    } else {
        Write-Action1Log "Request body: (none)" -Level TRACE
    }

    # TRACE: Log complete request summary
    Write-Action1Log "--- REQUEST SUMMARY ---" -Level TRACE
    Write-Action1Log "$Method $uri" -Level TRACE
    Write-Action1Log "Content-Type: application/json" -Level TRACE
    Write-Action1Log "Body size: $(if ($bodyJson) { $bodyJson.Length } else { 0 }) bytes" -Level TRACE
    Write-Action1Log "-----------------------" -Level TRACE

    try {
        Write-Action1Log "Executing API request..." -Level INFO
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        $response = Invoke-RestMethod @params

        $stopwatch.Stop()
        Write-Action1Log "API request completed successfully in $($stopwatch.ElapsedMilliseconds)ms" -Level INFO

        # TRACE: Log complete response details
        Write-Action1Log "--- RESPONSE SUMMARY ---" -Level TRACE
        Write-Action1Log "Status: Success" -Level TRACE
        Write-Action1Log "Duration: $($stopwatch.ElapsedMilliseconds)ms" -Level TRACE
        $responseJson = $response | ConvertTo-Json -Depth 10 -Compress
        Write-Action1Log "Response size: $($responseJson.Length) bytes" -Level TRACE
        Write-Action1Log "------------------------" -Level TRACE
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

function Format-NestedObject {
    <#
    .SYNOPSIS
        Formats a nested object or array into a readable indented string.

    .DESCRIPTION
        Helper function that converts complex nested objects into human-readable
        indented text format for display purposes.

    .PARAMETER Object
        The object to format.

    .PARAMETER Indent
        The current indentation level (used for recursion).

    .PARAMETER IndentString
        The string to use for each indentation level.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Object,

        [Parameter()]
        [int]$Indent = 0,

        [Parameter()]
        [string]$IndentString = '    '
    )

    if ($null -eq $Object) {
        return ''
    }

    $prefix = $IndentString * $Indent
    $lines = @()

    # Handle arrays
    if ($Object -is [System.Collections.IEnumerable] -and $Object -isnot [string] -and $Object -isnot [System.Collections.IDictionary]) {
        $index = 0
        foreach ($item in $Object) {
            if ($item -is [PSCustomObject] -or $item -is [System.Collections.IDictionary]) {
                $lines += "${prefix}[$index]:"
                $lines += Format-NestedObject -Object $item -Indent ($Indent + 1) -IndentString $IndentString
            }
            else {
                $lines += "${prefix}[$index]: $item"
            }
            $index++
        }
    }
    # Handle PSCustomObject or hashtable
    elseif ($Object -is [PSCustomObject] -or $Object -is [System.Collections.IDictionary]) {
        $props = if ($Object -is [PSCustomObject]) { $Object.PSObject.Properties } else { $Object.GetEnumerator() }
        foreach ($prop in $props) {
            $name = if ($Object -is [PSCustomObject]) { $prop.Name } else { $prop.Key }
            $value = if ($Object -is [PSCustomObject]) { $prop.Value } else { $prop.Value }

            # Skip very long script content for cleaner display
            if ($name -match 'script_text|script_content' -and $value -is [string] -and $value.Length -gt 100) {
                $lines += "${prefix}${name}: <script content, $($value.Length) chars>"
                continue
            }

            if ($null -eq $value -or $value -eq '') {
                $lines += "${prefix}${name}: "
            }
            elseif ($value -is [PSCustomObject] -or $value -is [System.Collections.IDictionary]) {
                $lines += "${prefix}${name}:"
                $lines += Format-NestedObject -Object $value -Indent ($Indent + 1) -IndentString $IndentString
            }
            elseif ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                $lines += "${prefix}${name}:"
                $lines += Format-NestedObject -Object $value -Indent ($Indent + 1) -IndentString $IndentString
            }
            else {
                $lines += "${prefix}${name}: $value"
            }
        }
    }
    else {
        $lines += "${prefix}$Object"
    }

    return $lines -join "`n"
}

function Expand-NestedJsonAttributes {
    <#
    .SYNOPSIS
        Expands nested JSON attributes into flattened, user-friendly properties.

    .DESCRIPTION
        Takes an API response object and flattens nested structures like file_name
        (which contains platform-keyed objects) into readable properties.
        This function is designed to be reusable across multiple API response types.

    .PARAMETER InputObject
        The PSObject to expand. Can be a single object or an array.

    .PARAMETER ExpandFileNames
        If specified, expands the file_name property which contains platform-keyed objects.

    .PARAMETER FormatNested
        If specified, formats nested objects (like additional_actions) into readable indented strings.

    .EXAMPLE
        $version | Expand-NestedJsonAttributes -ExpandFileNames
        # Expands file_name: {Windows32: {name: "app.exe"}} into Files array

    .EXAMPLE
        Get-Action1App | Expand-NestedJsonAttributes -ExpandFileNames -FormatNested
        # Processes objects and formats nested attributes readably
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter()]
        [switch]$ExpandFileNames,

        [Parameter()]
        [switch]$FormatNested
    )

    process {
        if ($null -eq $InputObject) {
            return $null
        }

        # Handle arrays by processing each item
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string] -and $InputObject -isnot [System.Collections.IDictionary]) {
            foreach ($item in $InputObject) {
                Expand-NestedJsonAttributes -InputObject $item -ExpandFileNames:$ExpandFileNames -FormatNested:$FormatNested
            }
            return
        }

        # Clone the object to avoid modifying the original
        $expanded = [PSCustomObject]@{}

        foreach ($prop in $InputObject.PSObject.Properties) {
            $propName = $prop.Name
            $propValue = $prop.Value

            # Handle file_name expansion
            if ($ExpandFileNames -and $propName -eq 'file_name' -and $propValue -is [PSCustomObject]) {
                # Extract files from platform-keyed structure
                $files = @()
                foreach ($platformProp in $propValue.PSObject.Properties) {
                    $platform = $platformProp.Name
                    $fileInfo = $platformProp.Value

                    if ($fileInfo -is [PSCustomObject]) {
                        $files += [PSCustomObject]@{
                            Platform = $platform
                            FileName = $fileInfo.name
                            FileType = $fileInfo.type
                        }
                    }
                }

                # Add flattened Files array (formatted if requested)
                if ($FormatNested) {
                    $formattedFiles = Format-NestedObject -Object $files
                    $expanded | Add-Member -NotePropertyName 'Files' -NotePropertyValue $formattedFiles
                }
                else {
                    $expanded | Add-Member -NotePropertyName 'Files' -NotePropertyValue $files
                }

                # Add convenience properties (always plural for consistency)
                if ($files.Count -eq 1) {
                    $expanded | Add-Member -NotePropertyName 'FileNames' -NotePropertyValue $files[0].FileName
                    $expanded | Add-Member -NotePropertyName 'FileTypes' -NotePropertyValue $files[0].FileType
                    $expanded | Add-Member -NotePropertyName 'Platforms' -NotePropertyValue $files[0].Platform
                }
                elseif ($files.Count -gt 1) {
                    # For multi-platform, create arrays/summary strings
                    $expanded | Add-Member -NotePropertyName 'FileNames' -NotePropertyValue ($files.FileName -join '; ')
                    $expanded | Add-Member -NotePropertyName 'FileTypes' -NotePropertyValue (($files.FileType | Select-Object -Unique) -join ', ')
                    $expanded | Add-Member -NotePropertyName 'Platforms' -NotePropertyValue ($files.Platform -join ', ')
                }
            }
            # Handle binary_id similarly (it has the same platform-keyed structure)
            elseif ($ExpandFileNames -and $propName -eq 'binary_id' -and $propValue -is [PSCustomObject]) {
                $binaryIds = @()
                foreach ($platformProp in $propValue.PSObject.Properties) {
                    $binaryIds += [PSCustomObject]@{
                        Platform = $platformProp.Name
                        BinaryId = $platformProp.Value
                    }
                }
                if ($FormatNested) {
                    $formattedBinaryIds = Format-NestedObject -Object $binaryIds
                    $expanded | Add-Member -NotePropertyName 'BinaryIds' -NotePropertyValue $formattedBinaryIds
                }
                else {
                    $expanded | Add-Member -NotePropertyName 'BinaryIds' -NotePropertyValue $binaryIds
                }
            }
            # Handle additional_actions with friendly formatting
            elseif ($propName -eq 'additional_actions' -and $propValue -is [System.Collections.IEnumerable]) {
                # Create expanded actions with resolved names
                $expandedActions = @()
                foreach ($action in $propValue) {
                    # Try to resolve a friendly name from params
                    $friendlyName = $action.name
                    if ($action.params) {
                        if ($action.params.display_summary) {
                            $friendlyName = "$($action.name): $($action.params.display_summary)"
                        }
                        elseif ($action.params.run_script_id) {
                            # Extract name from run_script_id (e.g., "Check_System_Requirements_1768639966107" -> "Check System Requirements")
                            $scriptName = $action.params.run_script_id -replace '_\d+$', '' -replace '_', ' '
                            $friendlyName = "$($action.name): $scriptName"
                        }
                    }

                    # Build a cleaner action object
                    $cleanAction = [PSCustomObject]@{
                        Name       = $friendlyName
                        When       = $action.when
                        Priority   = $action.priority
                        TemplateId = $action.template_id
                        Id         = $action.id
                    }

                    # Add script info if available
                    if ($action.params.run_script_language) {
                        $cleanAction | Add-Member -NotePropertyName 'Language' -NotePropertyValue $action.params.run_script_language
                    }
                    if ($action.params.platform) {
                        $cleanAction | Add-Member -NotePropertyName 'Platform' -NotePropertyValue $action.params.platform
                    }

                    $expandedActions += $cleanAction
                }

                if ($FormatNested) {
                    # Format as readable string
                    $formattedOutput = Format-NestedObject -Object $expandedActions
                    $expanded | Add-Member -NotePropertyName 'AdditionalActions' -NotePropertyValue $formattedOutput
                }
                else {
                    $expanded | Add-Member -NotePropertyName 'AdditionalActions' -NotePropertyValue $expandedActions
                }
            }
            # Handle scoped_approvals with formatting
            elseif ($FormatNested -and $propName -eq 'scoped_approvals' -and $propValue -is [System.Collections.IEnumerable]) {
                $formattedOutput = Format-NestedObject -Object $propValue
                $expanded | Add-Member -NotePropertyName 'ScopedApprovals' -NotePropertyValue $formattedOutput
            }
            # Handle arrays of simple values (strings, numbers) - join them nicely
            elseif ($propValue -is [System.Collections.IEnumerable] -and $propValue -isnot [string]) {
                # Check if it's a simple array (all items are primitives)
                $isSimpleArray = $true
                $hasComplexItems = $false
                foreach ($item in $propValue) {
                    if ($item -is [PSCustomObject] -or ($item -is [System.Collections.IEnumerable] -and $item -isnot [string])) {
                        $hasComplexItems = $true
                        $isSimpleArray = $false
                        break
                    }
                }

                if ($isSimpleArray) {
                    # Simple array - join as comma-separated string for readability
                    $joined = ($propValue | ForEach-Object { "$_" }) -join ', '
                    $expanded | Add-Member -NotePropertyName $propName -NotePropertyValue $joined
                }
                elseif ($FormatNested -and $hasComplexItems) {
                    # Complex array with nested objects - format nicely
                    $formattedOutput = Format-NestedObject -Object $propValue
                    $expanded | Add-Member -NotePropertyName $propName -NotePropertyValue $formattedOutput
                }
                else {
                    # Keep as-is
                    $expanded | Add-Member -NotePropertyName $propName -NotePropertyValue $propValue
                }
            }
            # Handle other PSCustomObjects with FormatNested
            elseif ($FormatNested -and $propValue -is [PSCustomObject]) {
                # Format complex nested objects
                $formattedOutput = Format-NestedObject -Object $propValue
                $expanded | Add-Member -NotePropertyName $propName -NotePropertyValue $formattedOutput
            }
            else {
                # Copy other properties as-is
                $expanded | Add-Member -NotePropertyName $propName -NotePropertyValue $propValue
            }
        }

        return $expanded
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

#region Installer Metadata Extraction Functions

function Get-MsiMetadata {
    <#
    .SYNOPSIS
        Extracts metadata from MSI installer files by querying the MSI database.

    .DESCRIPTION
        Uses the WindowsInstaller.Installer COM object to query the Property table
        of an MSI file for ProductName, ProductVersion, Manufacturer, and other metadata.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Write-Action1Log "Attempting to extract MSI database metadata from: $Path" -Level DEBUG

    $result = @{
        Success = $false
        ProductName = $null
        ProductVersion = $null
        Manufacturer = $null
        Description = $null
        Source = "MSI Database"
    }

    try {
        $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $database = $windowsInstaller.GetType().InvokeMember(
            "OpenDatabase",
            [System.Reflection.BindingFlags]::InvokeMethod,
            $null,
            $windowsInstaller,
            @($Path, 0)  # 0 = msiOpenDatabaseModeReadOnly
        )

        # Query the Property table for metadata
        $propertyQuery = "SELECT Property, Value FROM Property WHERE Property IN ('ProductName', 'ProductVersion', 'Manufacturer', 'ARPCOMMENTS', 'ProductCode')"

        $view = $database.GetType().InvokeMember(
            "OpenView",
            [System.Reflection.BindingFlags]::InvokeMethod,
            $null,
            $database,
            @($propertyQuery)
        )

        $view.GetType().InvokeMember(
            "Execute",
            [System.Reflection.BindingFlags]::InvokeMethod,
            $null,
            $view,
            $null
        )

        $properties = @{}
        do {
            $record = $view.GetType().InvokeMember(
                "Fetch",
                [System.Reflection.BindingFlags]::InvokeMethod,
                $null,
                $view,
                $null
            )

            if ($null -ne $record) {
                $propertyName = $record.GetType().InvokeMember(
                    "StringData",
                    [System.Reflection.BindingFlags]::GetProperty,
                    $null,
                    $record,
                    @(1)
                )
                $propertyValue = $record.GetType().InvokeMember(
                    "StringData",
                    [System.Reflection.BindingFlags]::GetProperty,
                    $null,
                    $record,
                    @(2)
                )
                $properties[$propertyName] = $propertyValue
            }
        } while ($null -ne $record)

        $view.GetType().InvokeMember("Close", [System.Reflection.BindingFlags]::InvokeMethod, $null, $view, $null)

        # Release COM objects
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($view) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($database) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($windowsInstaller) | Out-Null

        if ($properties.Count -gt 0) {
            $result.ProductName = $properties['ProductName']
            $result.ProductVersion = $properties['ProductVersion']
            $result.Manufacturer = $properties['Manufacturer']
            $result.Description = $properties['ARPCOMMENTS']
            $result.Success = ($null -ne $result.ProductName -or $null -ne $result.ProductVersion)

            Write-Action1Log "MSI database metadata extracted successfully" -Level DEBUG -Data $properties
        }
    }
    catch {
        Write-Action1Log "Failed to extract MSI database metadata" -Level DEBUG -ErrorRecord $_
    }

    return $result
}

function Get-DigitalSignatureMetadata {
    <#
    .SYNOPSIS
        Extracts metadata from the digital signature/code signing certificate of an installer.

    .DESCRIPTION
        Parses the Authenticode signature to extract publisher information from the
        signing certificate's subject field.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Write-Action1Log "Attempting to extract digital signature metadata from: $Path" -Level DEBUG

    $result = @{
        Success = $false
        Publisher = $null
        Subject = $null
        Issuer = $null
        SignatureStatus = $null
        Source = "Digital Signature"
    }

    try {
        $signature = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop

        if ($signature.Status -ne 'NotSigned' -and $null -ne $signature.SignerCertificate) {
            $result.SignatureStatus = $signature.Status.ToString()
            $result.Subject = $signature.SignerCertificate.Subject
            $result.Issuer = $signature.SignerCertificate.Issuer

            # Parse the subject to extract organization/company name
            # Subject format: CN=Company Name, O=Organization, L=City, S=State, C=Country
            $subject = $signature.SignerCertificate.Subject

            # Try to extract O (Organization) first, then CN (Common Name)
            if ($subject -match 'O=([^,]+)') {
                $result.Publisher = $matches[1].Trim().Trim('"')
            }
            elseif ($subject -match 'CN=([^,]+)') {
                $result.Publisher = $matches[1].Trim().Trim('"')
            }

            $result.Success = ($null -ne $result.Publisher)

            Write-Action1Log "Digital signature metadata extracted" -Level DEBUG -Data @{
                Publisher = $result.Publisher
                Status = $result.SignatureStatus
                Subject = $result.Subject
            }
        }
        else {
            Write-Action1Log "File is not signed or signature is invalid" -Level DEBUG
        }
    }
    catch {
        Write-Action1Log "Failed to extract digital signature metadata" -Level DEBUG -ErrorRecord $_
    }

    return $result
}

function Get-InnoSetupMetadata {
    <#
    .SYNOPSIS
        Extracts metadata from Inno Setup installers.

    .DESCRIPTION
        Detects Inno Setup installers by signature and attempts to extract
        embedded setup information including AppName, AppVersion, AppPublisher.
        Uses binary pattern matching to find the embedded setup script data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Write-Action1Log "Attempting to extract Inno Setup metadata from: $Path" -Level DEBUG

    $result = @{
        Success = $false
        ProductName = $null
        ProductVersion = $null
        Publisher = $null
        InstallerType = $null
        Source = "Inno Setup"
    }

    try {
        # Read the first portion of the file to check for Inno Setup signatures
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $fileContent = [System.Text.Encoding]::ASCII.GetString($bytes[0..([Math]::Min(2MB, $bytes.Length - 1))])

        # Check for Inno Setup signatures
        $isInnoSetup = $false
        $innoSignatures = @(
            'Inno Setup',
            'InnoSetupVersion',
            'Inno Setup Setup Data',
            'inno.exe'
        )

        foreach ($sig in $innoSignatures) {
            if ($fileContent -match [regex]::Escape($sig)) {
                $isInnoSetup = $true
                $result.InstallerType = "Inno Setup"
                break
            }
        }

        if (-not $isInnoSetup) {
            Write-Action1Log "File does not appear to be an Inno Setup installer" -Level DEBUG
            return $result
        }

        Write-Action1Log "Inno Setup signature detected, extracting metadata..." -Level DEBUG

        # Try to find embedded script data patterns
        # Inno Setup stores strings in a specific format, often with null-terminated or length-prefixed strings

        # Look for common Inno Setup script patterns in the binary
        $patterns = @{
            'AppName' = 'AppName=([^\x00\r\n]+)'
            'AppVersion' = 'AppVersion=([^\x00\r\n]+)'
            'AppVerName' = 'AppVerName=([^\x00\r\n]+)'
            'AppPublisher' = 'AppPublisher=([^\x00\r\n]+)'
            'AppPublisherURL' = 'AppPublisherURL=([^\x00\r\n]+)'
            'DefaultDirName' = 'DefaultDirName=([^\x00\r\n]+)'
        }

        $foundValues = @{}
        foreach ($key in $patterns.Keys) {
            if ($fileContent -match $patterns[$key]) {
                $value = $matches[1].Trim()
                # Clean up the value - remove any binary garbage
                $value = $value -replace '[^\x20-\x7E]', ''
                if ($value.Length -gt 0 -and $value.Length -lt 200) {
                    $foundValues[$key] = $value
                }
            }
        }

        # Also try to find version info from common patterns
        if (-not $foundValues['AppVersion']) {
            # Try pattern like "1.2.3" or "v1.2.3" near AppName or version markers
            if ($fileContent -match 'ersion[=:\s]+v?(\d+\.\d+(?:\.\d+)?(?:\.\d+)?)') {
                $foundValues['AppVersion'] = $matches[1]
            }
        }

        if ($foundValues.Count -gt 0) {
            $result.ProductName = $foundValues['AppName']
            $result.ProductVersion = $foundValues['AppVersion']
            $result.Publisher = $foundValues['AppPublisher']

            # AppVerName often contains both name and version
            if (-not $result.ProductName -and $foundValues['AppVerName']) {
                $verName = $foundValues['AppVerName']
                # Try to split "AppName v1.2.3" or "AppName 1.2.3"
                if ($verName -match '^(.+?)\s+v?(\d+\.\d+.*)$') {
                    $result.ProductName = $matches[1]
                    if (-not $result.ProductVersion) {
                        $result.ProductVersion = $matches[2]
                    }
                }
                else {
                    $result.ProductName = $verName
                }
            }

            $result.Success = ($null -ne $result.ProductName -or $null -ne $result.ProductVersion -or $null -ne $result.Publisher)

            Write-Action1Log "Inno Setup metadata extracted" -Level DEBUG -Data $foundValues
        }
    }
    catch {
        Write-Action1Log "Failed to extract Inno Setup metadata" -Level DEBUG -ErrorRecord $_
    }

    return $result
}

function Get-NsisMetadata {
    <#
    .SYNOPSIS
        Extracts metadata from NSIS (Nullsoft Scriptable Install System) installers.

    .DESCRIPTION
        Detects NSIS installers by signature and attempts to extract
        embedded metadata including product name, version, and publisher.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Write-Action1Log "Attempting to extract NSIS metadata from: $Path" -Level DEBUG

    $result = @{
        Success = $false
        ProductName = $null
        ProductVersion = $null
        Publisher = $null
        InstallerType = $null
        Source = "NSIS"
    }

    try {
        # Read the file content
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $fileContent = [System.Text.Encoding]::ASCII.GetString($bytes[0..([Math]::Min(2MB, $bytes.Length - 1))])

        # Check for NSIS signatures
        $isNsis = $false
        $nsisSignatures = @(
            'NullsoftInst',
            'Nullsoft Install System',
            'NSIS Error',
            'nsis.sf.net'
        )

        foreach ($sig in $nsisSignatures) {
            if ($fileContent -match [regex]::Escape($sig)) {
                $isNsis = $true
                $result.InstallerType = "NSIS"
                break
            }
        }

        if (-not $isNsis) {
            Write-Action1Log "File does not appear to be an NSIS installer" -Level DEBUG
            return $result
        }

        Write-Action1Log "NSIS signature detected, extracting metadata..." -Level DEBUG

        # NSIS installers often have strings embedded that we can extract
        # Look for common patterns

        # Try to find Name and Version from NSIS script defines
        # NSIS uses !define statements which may be embedded

        $patterns = @{
            'PRODUCT_NAME' = '(?:PRODUCT_NAME|APP_NAME|NAME)[="\s]+([^\x00\r\n"]+)'
            'PRODUCT_VERSION' = '(?:PRODUCT_VERSION|APP_VERSION|VERSION)[="\s]+v?([0-9][^\x00\r\n"]*)'
            'PRODUCT_PUBLISHER' = '(?:PRODUCT_PUBLISHER|PUBLISHER|COMPANY)[="\s]+([^\x00\r\n"]+)'
        }

        $foundValues = @{}
        foreach ($key in $patterns.Keys) {
            if ($fileContent -match $patterns[$key]) {
                $value = $matches[1].Trim().Trim('"')
                $value = $value -replace '[^\x20-\x7E]', ''
                if ($value.Length -gt 0 -and $value.Length -lt 200) {
                    $foundValues[$key] = $value
                }
            }
        }

        # Also look for branding text which often contains product info
        if ($fileContent -match 'Nullsoft Install System v[\d.]+') {
            # Try to find the installer title near the beginning
            if ($fileContent -match '(?<=\x00)([A-Za-z][A-Za-z0-9\s\-_.]+(?:Setup|Install(?:er)?|v?\d+\.\d+)[A-Za-z0-9\s\-_.]*?)(?=\x00)') {
                $potentialName = $matches[1].Trim()
                if ($potentialName.Length -gt 3 -and $potentialName.Length -lt 100 -and -not $foundValues['PRODUCT_NAME']) {
                    $foundValues['PRODUCT_NAME'] = $potentialName -replace '\s*(Setup|Installer?)$', ''
                }
            }
        }

        if ($foundValues.Count -gt 0) {
            $result.ProductName = $foundValues['PRODUCT_NAME']
            $result.ProductVersion = $foundValues['PRODUCT_VERSION']
            $result.Publisher = $foundValues['PRODUCT_PUBLISHER']
            $result.Success = ($null -ne $result.ProductName -or $null -ne $result.ProductVersion -or $null -ne $result.Publisher)

            Write-Action1Log "NSIS metadata extracted" -Level DEBUG -Data $foundValues
        }
    }
    catch {
        Write-Action1Log "Failed to extract NSIS metadata" -Level DEBUG -ErrorRecord $_
    }

    return $result
}

function Get-FileVersionMetadata {
    <#
    .SYNOPSIS
        Extracts metadata from PE file version information resources.

    .DESCRIPTION
        Uses System.Diagnostics.FileVersionInfo to read the standard Windows
        version resource embedded in PE files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Write-Action1Log "Extracting file version info metadata from: $Path" -Level DEBUG

    $result = @{
        Success = $false
        ProductName = $null
        ProductVersion = $null
        FileVersion = $null
        Publisher = $null
        Description = $null
        Source = "File Version Info"
    }

    try {
        $fileVersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)

        $result.ProductName = if ($fileVersionInfo.ProductName) { $fileVersionInfo.ProductName.Trim() } else { $null }
        $result.ProductVersion = if ($fileVersionInfo.ProductVersion) {
            ($fileVersionInfo.ProductVersion -split '[\s\-]')[0].Trim()
        } else { $null }
        $result.FileVersion = if ($fileVersionInfo.FileVersion) {
            ($fileVersionInfo.FileVersion -split '[\s\-]')[0].Trim()
        } else { $null }
        $result.Publisher = if ($fileVersionInfo.CompanyName) { $fileVersionInfo.CompanyName.Trim() } else { $null }
        $result.Description = if ($fileVersionInfo.FileDescription) { $fileVersionInfo.FileDescription.Trim() } else { $null }

        $result.Success = ($null -ne $result.ProductName -or $null -ne $result.ProductVersion -or $null -ne $result.Publisher)

        Write-Action1Log "File version info metadata extracted" -Level DEBUG -Data @{
            ProductName = $result.ProductName
            ProductVersion = $result.ProductVersion
            FileVersion = $result.FileVersion
            Publisher = $result.Publisher
            Description = $result.Description
        }
    }
    catch {
        Write-Action1Log "Failed to extract file version info metadata" -Level DEBUG -ErrorRecord $_
    }

    return $result
}

function Get-InstallerMetadata {
    <#
    .SYNOPSIS
        Comprehensive metadata extraction from installer files with multiple fallback methods.

    .DESCRIPTION
        Attempts to extract metadata from installers using multiple techniques:
        1. MSI database querying (for .msi files)
        2. PE file version information
        3. Digital signature certificate parsing
        4. Inno Setup script extraction
        5. NSIS installer detection and extraction

        Results are merged with priority given to more reliable sources.

    .PARAMETER Path
        Path to the installer file (.exe or .msi)

    .EXAMPLE
        $metadata = Get-InstallerMetadata -Path "C:\Downloads\setup.exe"
        Write-Host "Product: $($metadata.ProductName) v$($metadata.ProductVersion) by $($metadata.Publisher)"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Installer file not found: $Path"
    }

    $installerFile = Get-Item $Path
    $extension = $installerFile.Extension.ToLower()

    Write-Action1Log "Starting comprehensive metadata extraction for: $($installerFile.Name)" -Level INFO

    # Initialize result with defaults
    $result = @{
        ProductName = $null
        ProductVersion = $null
        Publisher = $null
        Description = $null
        InstallerType = $null
        Sources = @()
        AllMetadata = @{}
    }

    # Collection of all extraction results for debugging/logging
    $extractionResults = @()

    # 1. MSI Database (highest priority for MSI files)
    if ($extension -eq '.msi') {
        Write-Host "  Querying MSI database..." -ForegroundColor Gray
        $msiResult = Get-MsiMetadata -Path $Path
        $extractionResults += $msiResult
        $result.AllMetadata['MSI'] = $msiResult

        if ($msiResult.Success) {
            $result.Sources += "MSI Database"
            if (-not $result.ProductName -and $msiResult.ProductName) { $result.ProductName = $msiResult.ProductName }
            if (-not $result.ProductVersion -and $msiResult.ProductVersion) { $result.ProductVersion = $msiResult.ProductVersion }
            if (-not $result.Publisher -and $msiResult.Manufacturer) { $result.Publisher = $msiResult.Manufacturer }
            if (-not $result.Description -and $msiResult.Description) { $result.Description = $msiResult.Description }
            $result.InstallerType = "MSI"
        }
    }

    # 2. File Version Info (works for both EXE and MSI)
    Write-Host "  Reading file version information..." -ForegroundColor Gray
    $versionResult = Get-FileVersionMetadata -Path $Path
    $extractionResults += $versionResult
    $result.AllMetadata['FileVersion'] = $versionResult

    if ($versionResult.Success) {
        $result.Sources += "File Version Info"
        if (-not $result.ProductName -and $versionResult.ProductName) { $result.ProductName = $versionResult.ProductName }
        if (-not $result.ProductVersion -and $versionResult.ProductVersion) { $result.ProductVersion = $versionResult.ProductVersion }
        if (-not $result.ProductVersion -and $versionResult.FileVersion) { $result.ProductVersion = $versionResult.FileVersion }
        if (-not $result.Publisher -and $versionResult.Publisher) { $result.Publisher = $versionResult.Publisher }
        if (-not $result.Description -and $versionResult.Description) { $result.Description = $versionResult.Description }
    }

    # 3. Digital Signature (good for publisher info)
    Write-Host "  Checking digital signature..." -ForegroundColor Gray
    $sigResult = Get-DigitalSignatureMetadata -Path $Path
    $extractionResults += $sigResult
    $result.AllMetadata['DigitalSignature'] = $sigResult

    if ($sigResult.Success) {
        $result.Sources += "Digital Signature"
        # Only use signature for publisher if we don't have one yet
        if (-not $result.Publisher -and $sigResult.Publisher) { $result.Publisher = $sigResult.Publisher }
    }

    # 4. Inno Setup detection and extraction (for EXE files)
    if ($extension -eq '.exe') {
        Write-Host "  Checking for Inno Setup installer..." -ForegroundColor Gray
        $innoResult = Get-InnoSetupMetadata -Path $Path
        $extractionResults += $innoResult
        $result.AllMetadata['InnoSetup'] = $innoResult

        if ($innoResult.Success) {
            $result.Sources += "Inno Setup"
            $result.InstallerType = "Inno Setup"
            if (-not $result.ProductName -and $innoResult.ProductName) { $result.ProductName = $innoResult.ProductName }
            if (-not $result.ProductVersion -and $innoResult.ProductVersion) { $result.ProductVersion = $innoResult.ProductVersion }
            if (-not $result.Publisher -and $innoResult.Publisher) { $result.Publisher = $innoResult.Publisher }
        }

        # 5. NSIS detection and extraction (for EXE files, if not Inno)
        if (-not $innoResult.Success -or -not $result.InstallerType) {
            Write-Host "  Checking for NSIS installer..." -ForegroundColor Gray
            $nsisResult = Get-NsisMetadata -Path $Path
            $extractionResults += $nsisResult
            $result.AllMetadata['NSIS'] = $nsisResult

            if ($nsisResult.Success) {
                $result.Sources += "NSIS"
                if (-not $result.InstallerType) { $result.InstallerType = "NSIS" }
                if (-not $result.ProductName -and $nsisResult.ProductName) { $result.ProductName = $nsisResult.ProductName }
                if (-not $result.ProductVersion -and $nsisResult.ProductVersion) { $result.ProductVersion = $nsisResult.ProductVersion }
                if (-not $result.Publisher -and $nsisResult.Publisher) { $result.Publisher = $nsisResult.Publisher }
            }
        }
    }

    # Set default installer type if not detected
    if (-not $result.InstallerType) {
        $result.InstallerType = switch ($extension) {
            '.msi' { 'MSI' }
            '.exe' { 'EXE' }
            default { 'Unknown' }
        }
    }

    # Apply final fallbacks
    if (-not $result.ProductName) {
        $result.ProductName = [System.IO.Path]::GetFileNameWithoutExtension($installerFile.Name)
        $result.Sources += "Filename (fallback)"
    }
    if (-not $result.ProductVersion) {
        $result.ProductVersion = "1.0.0"
        $result.Sources += "Default version (fallback)"
    }
    if (-not $result.Publisher) {
        $result.Publisher = "Unknown"
    }

    Write-Action1Log "Metadata extraction complete" -Level INFO -Data @{
        ProductName = $result.ProductName
        ProductVersion = $result.ProductVersion
        Publisher = $result.Publisher
        InstallerType = $result.InstallerType
        Sources = $result.Sources -join ', '
    }

    return $result
}

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

        Write-Action1Log "Profile path: $script:Action1ConfigDir" -Level DEBUG

        if (-not (Test-Path $script:Action1ConfigDir)) {
            Write-Action1Log "Creating profile directory" -Level DEBUG
            New-Item -Path $script:Action1ConfigDir -ItemType Directory -Force | Out-Null
        }

        $credFile = Join-Path $script:Action1ConfigDir "credentials.json"

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

function Get-Action1ApiCredentials {
    <#
    .SYNOPSIS
        Retrieves the current Action1 API credentials and validates permissions.

    .DESCRIPTION
        Returns information about the currently configured API credentials including
        region, endpoint, and token status. Optionally validates the credentials
        by making an API call to check accessible organizations and permissions.

    .PARAMETER TestConnection
        If specified, makes an API call to validate credentials and check permissions.

    .PARAMETER ShowSecret
        If specified, includes the client secret in the output (masked by default).

    .EXAMPLE
        Get-Action1ApiCredentials
        # Returns current credential info without API validation

    .EXAMPLE
        Get-Action1ApiCredentials -TestConnection
        # Returns credential info and validates by checking accessible organizations

    .EXAMPLE
        Get-Action1ApiCredentials -ShowSecret
        # Includes the client secret in the output
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$TestConnection,

        [Parameter()]
        [switch]$ShowSecret
    )

    Write-Action1Log "Retrieving Action1 API credentials" -Level INFO

    # Check if credentials are configured
    $isConfigured = $null -ne $script:Action1ClientId -and $null -ne $script:Action1ClientSecret

    if (-not $isConfigured) {
        Write-Action1Log "No credentials configured" -Level WARN
        Write-Host "No Action1 API credentials configured." -ForegroundColor Yellow
        Write-Host "Use Set-Action1ApiCredentials to configure." -ForegroundColor Cyan
        return [PSCustomObject]@{
            Configured     = $false
            ClientId       = $null
            Region         = $null
            Endpoint       = $null
            TokenStatus    = 'Not Available'
            Organizations  = @()
            Permissions    = @()
        }
    }

    # Build credential info object
    $credInfo = [PSCustomObject]@{
        Configured     = $true
        ClientId       = $script:Action1ClientId
        ClientSecret   = if ($ShowSecret) { $script:Action1ClientSecret } else { '********' }
        Region         = $script:Action1Region
        Endpoint       = $script:Action1BaseUri
        TokenStatus    = 'Unknown'
        TokenExpiry    = $null
        Organizations  = @()
        Permissions    = @()
    }

    # Check token status
    if ($script:Action1AccessToken) {
        if ($script:Action1TokenExpiry -and (Get-Date) -lt $script:Action1TokenExpiry) {
            $credInfo.TokenStatus = 'Valid'
            $credInfo.TokenExpiry = $script:Action1TokenExpiry
        }
        else {
            $credInfo.TokenStatus = 'Expired'
            $credInfo.TokenExpiry = $script:Action1TokenExpiry
        }
    }
    else {
        $credInfo.TokenStatus = 'Not Acquired'
    }

    Write-Action1Log "Credentials configured for region: $($script:Action1Region)" -Level DEBUG

    # If TestConnection requested, validate by calling API
    if ($TestConnection) {
        Write-Action1Log "Testing connection and checking permissions..." -Level INFO
        Write-Host "`nValidating credentials..." -ForegroundColor Cyan

        try {
            # Get organizations to validate credentials and check access
            $orgsResponse = Invoke-Action1ApiRequest -Endpoint "organizations" -Method GET
            $orgs = if ($orgsResponse.items) { @($orgsResponse.items) } else { @($orgsResponse) }

            $credInfo.Organizations = $orgs | ForEach-Object {
                [PSCustomObject]@{
                    Id   = $_.id
                    Name = $_.name
                    Type = $_.type
                }
            }

            # Update token status after successful call
            $credInfo.TokenStatus = 'Valid'
            $credInfo.TokenExpiry = $script:Action1TokenExpiry

            # Determine permissions based on accessible resources
            $permissions = @()

            # Check organizations access
            if ($orgs.Count -gt 0) {
                $permissions += 'Organizations:Read'
            }

            # Try to check software repository access (use first org or 'all')
            $testOrgId = if ($orgs.Count -gt 0) { $orgs[0].id } else { 'all' }
            try {
                $null = Invoke-Action1ApiRequest `
                    -Endpoint "software-repository/$testOrgId`?limit=1" `
                    -Method GET
                $permissions += 'SoftwareRepository:Read'
                Write-Action1Log "Software repository access confirmed" -Level DEBUG
            }
            catch {
                Write-Action1Log "No software repository read access" -Level DEBUG
            }

            # Try to check automations access
            try {
                $null = Invoke-Action1ApiRequest `
                    -Endpoint "automations/$testOrgId`?limit=1" `
                    -Method GET
                $permissions += 'Automations:Read'
                Write-Action1Log "Automations access confirmed" -Level DEBUG
            }
            catch {
                Write-Action1Log "No automations read access" -Level DEBUG
            }

            # Try to check endpoint groups access
            try {
                $null = Invoke-Action1ApiRequest `
                    -Endpoint "endpointgroups/$testOrgId`?limit=1" `
                    -Method GET
                $permissions += 'EndpointGroups:Read'
                Write-Action1Log "Endpoint groups access confirmed" -Level DEBUG
            }
            catch {
                Write-Action1Log "No endpoint groups read access" -Level DEBUG
            }

            $credInfo.Permissions = $permissions

            Write-Host "`n✓ Credentials validated successfully" -ForegroundColor Green
            Write-Host "`nAccessible Organizations:" -ForegroundColor Cyan
            foreach ($org in $credInfo.Organizations) {
                Write-Host "  - $($org.Name) ($($org.Id))" -ForegroundColor White
            }

            Write-Host "`nDetected Permissions:" -ForegroundColor Cyan
            foreach ($perm in $permissions) {
                Write-Host "  ✓ $perm" -ForegroundColor Green
            }
        }
        catch {
            Write-Action1Log "Failed to validate credentials" -Level ERROR -ErrorRecord $_
            Write-Host "`n✗ Failed to validate credentials: $($_.Exception.Message)" -ForegroundColor Red
            $credInfo.TokenStatus = 'Invalid'
        }
    }
    else {
        # Display basic info without API call
        Write-Host "`nAction1 API Credentials:" -ForegroundColor Cyan
        Write-Host "  Client ID:  $($credInfo.ClientId)" -ForegroundColor White
        Write-Host "  Region:     $($credInfo.Region)" -ForegroundColor White
        Write-Host "  Endpoint:   $($credInfo.Endpoint)" -ForegroundColor White
        Write-Host "  Token:      $($credInfo.TokenStatus)" -ForegroundColor $(if ($credInfo.TokenStatus -eq 'Valid') { 'Green' } elseif ($credInfo.TokenStatus -eq 'Expired') { 'Yellow' } else { 'Gray' })
        if ($credInfo.TokenExpiry) {
            Write-Host "  Expires:    $($credInfo.TokenExpiry)" -ForegroundColor Gray
        }
        Write-Host "`nUse -TestConnection to validate credentials and check permissions." -ForegroundColor DarkGray
    }

    return $credInfo
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
        including folders for installers, scripts, and a manifest file. Optionally creates
        the software repository in Action1 via API.

    .PARAMETER AppName
        The name of the application.

    .PARAMETER Path
        The path where the repository should be created. Defaults to current directory.

    .PARAMETER IncludeExamples
        If specified, includes example files and documentation.

    .PARAMETER CreateInAction1
        If specified, also creates the software repository in Action1 via API.

    .PARAMETER OrganizationId
        Action1 organization ID or "all" for all organizations.
        If not provided, will prompt for scope selection (defaults to "all").

    .PARAMETER Description
        Description for the Action1 software repository.

    .PARAMETER Publisher
        Publisher/vendor name for the application. Required when using -CreateInAction1.
        If not provided, will prompt for it.

    .PARAMETER Version
        Initial version number. Defaults to "1.0.0".

    .EXAMPLE
        New-Action1AppRepo -AppName "7-Zip"

    .EXAMPLE
        New-Action1AppRepo -AppName "PowerShell 7" -CreateInAction1
        # Will prompt for scope (defaults to "all" organizations)

    .EXAMPLE
        New-Action1AppRepo -AppName "PowerShell 7" -CreateInAction1 -OrganizationId "all"
        # Explicitly use all organizations scope

    .EXAMPLE
        New-Action1AppRepo -AppName "Visual Studio Code" -CreateInAction1 -OrganizationId "org_123" -Publisher "Microsoft" -Description "Code editor"
        # Use specific organization
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [Parameter()]
        [string]$Path = (Get-Location).Path,

        [Parameter()]
        [switch]$IncludeExamples,

        [Parameter()]
        [switch]$CreateInAction1,

        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$Publisher,

        [Parameter()]
        [string]$Version = "1.0.0"
    )

    Write-Action1Log "Creating new Action1 app repository for: $AppName" -Level INFO
    Write-Action1Log "Base path: $Path" -Level DEBUG
    Write-Action1Log "Include examples: $IncludeExamples" -Level DEBUG
    Write-Action1Log "Create in Action1: $CreateInAction1" -Level DEBUG

    # Sanitize name: remove invalid chars and replace spaces with underscores
    $sanitizedName = $AppName -replace '[\\/:*?"<>|]', '_' -replace '\s+', '_'
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
    
    # Create initial manifest with provided parameters
    $manifest = [PSCustomObject]@{
        AppName = $AppName
        Publisher = if ($Publisher) { $Publisher } else { "" }
        Description = if ($Description) { $Description } else { "" }
        Version = $Version
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
            OrganizationId = if ($OrganizationId) { $OrganizationId } else { "" }
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

    # Create software repository in Action1 if requested
    $action1PackageId = $null
    if ($CreateInAction1) {
        Write-Action1Log "Creating software repository in Action1" -Level INFO
        Write-Host "`n--- Creating Action1 Software Repository ---" -ForegroundColor Cyan

        # Prompt for organization scope if not provided
        if (-not $OrganizationId) {
            Write-Host "`nOrganization Scope:" -ForegroundColor Yellow
            Write-Host "  [1] All Organizations (default)" -ForegroundColor White
            Write-Host "  [2] Specific Organization" -ForegroundColor White

            $scopeSelection = Read-Host "`nSelect scope (1-2, default: 1)"

            if ($scopeSelection -eq '2') {
                # User wants specific organization - fetch and show list
                try {
                    Write-Host "`nFetching available organizations..." -ForegroundColor Gray
                    $orgsResponse = Invoke-Action1ApiRequest -Endpoint "organizations" -Method GET
                    $orgs = @($orgsResponse)

                    if ($orgs.Count -eq 0) {
                        Write-Host "No organizations found. Using 'all' scope." -ForegroundColor Yellow
                        $OrganizationId = "all"
                    } elseif ($orgs.Count -eq 1) {
                        $OrganizationId = $orgs[0].id
                        Write-Host "Using organization: $($orgs[0].name) ($OrganizationId)" -ForegroundColor Green
                    } else {
                        Write-Host "`nAvailable organizations:" -ForegroundColor Yellow
                        for ($i = 0; $i -lt $orgs.Count; $i++) {
                            Write-Host "  [$($i + 1)] $($orgs[$i].name) ($($orgs[$i].id))"
                        }
                        $orgSelection = Read-Host "`nSelect organization (1-$($orgs.Count))"
                        $selectedIndex = [int]$orgSelection - 1
                        if ($selectedIndex -ge 0 -and $selectedIndex -lt $orgs.Count) {
                            $OrganizationId = $orgs[$selectedIndex].id
                            Write-Host "Selected: $($orgs[$selectedIndex].name)" -ForegroundColor Green
                        } else {
                            Write-Host "Invalid selection. Using 'all' scope." -ForegroundColor Yellow
                            $OrganizationId = "all"
                        }
                    }
                }
                catch {
                    Write-Action1Log "Failed to fetch organizations" -Level DEBUG -ErrorRecord $_
                    $OrganizationId = Read-Host "Enter Action1 Organization ID (or 'all' for all organizations)"
                    if (-not $OrganizationId) { $OrganizationId = "all" }
                }
            } else {
                # Default to 'all' organizations
                $OrganizationId = "all"
                Write-Host "Using scope: All Organizations" -ForegroundColor Green
            }
        }

        if (-not $Publisher) {
            $Publisher = Read-Host "Enter publisher/vendor (required)"
            if (-not $Publisher) {
                $Publisher = "Unknown"
                Write-Host "Using default vendor: Unknown" -ForegroundColor Yellow
            }
        }

        if (-not $Description) {
            $Description = Read-Host "Enter description (optional, press Enter to skip)"
        }

        # Create the software repository package in Action1
        try {
            $packageData = @{
                name = $AppName
                vendor = $Publisher
                description = if ($Description) { $Description } else { "Software repository for $AppName" }
            }

            Write-Action1Log "Creating software repository package" -Level DEBUG -Data $packageData

            $createResponse = Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId" `
                -Method POST `
                -Body $packageData

            $action1PackageId = $createResponse.id
            Write-Action1Log "Software repository created: $action1PackageId" -Level INFO

            # Update manifest with Action1 config
            $manifest.Action1Config.OrganizationId = $OrganizationId
            $manifest.Action1Config.PackageId = $action1PackageId
            $manifest.Publisher = if ($Publisher) { $Publisher } else { $manifest.Publisher }
            $manifest.Description = if ($Description) { $Description } else { $manifest.Description }
            Write-ManifestFile -Manifest $manifest -Path $manifestPath

            Write-Host "✓ Software repository created in Action1" -ForegroundColor Green
            Write-Host "  Package ID: $action1PackageId" -ForegroundColor Cyan
        }
        catch {
            Write-Action1Log "Failed to create software repository in Action1" -Level ERROR -ErrorRecord $_
            Write-Host "✗ Failed to create Action1 software repository: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  You can create it manually later or retry with -CreateInAction1" -ForegroundColor Yellow
        }
    }

    Write-Action1Log "Repository creation completed successfully" -Level INFO
    Write-Host "`n✓ Action1 app repository created successfully!" -ForegroundColor Green
    Write-Host "Location: $repoPath" -ForegroundColor Cyan
    if ($action1PackageId) {
        Write-Host "Action1 Package ID: $action1PackageId" -ForegroundColor Cyan
    }
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "1. Place your installer in: $(Join-Path $repoPath 'installers')"
    Write-Host "2. Edit manifest.json to configure deployment settings"
    Write-Host "3. Run New-Action1AppPackage to prepare for deployment"

    return $repoPath
}

function New-Action1AppPackage {
    <#
    .SYNOPSIS
        Creates a new Action1 application package from an installer file.

    .DESCRIPTION
        Automatically scrapes application metadata (name, version, vendor) from installer
        file properties, prompts for silent install arguments, creates the package folder
        structure in /vendor/app/version/ format, and generates a manifest file.

    .PARAMETER InstallerPath
        Path to the installer file (.exe or .msi).

    .PARAMETER BasePath
        Base path where the package folder structure will be created.
        Defaults to current directory.

    .PARAMETER InstallSwitches
        Silent install arguments. If not provided, will prompt interactively.

    .PARAMETER UninstallSwitches
        Silent uninstall arguments. Optional.

    .PARAMETER SkipPrompt
        If specified, skips the prompt for silent install arguments and uses defaults.

    .EXAMPLE
        New-Action1AppPackage -InstallerPath "C:\Downloads\7z2301-x64.exe"

    .EXAMPLE
        New-Action1AppPackage -InstallerPath "C:\Downloads\vlc-3.0.18-win64.msi" -BasePath "C:\Packages" -InstallSwitches "/qn /norestart"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$InstallerPath,

        [Parameter()]
        [string]$BasePath = (Get-Location).Path,

        [Parameter()]
        [string]$InstallSwitches,

        [Parameter()]
        [string]$UninstallSwitches,

        [Parameter()]
        [switch]$SkipPrompt
    )

    Write-Host "`n=== Action1 Application Packager ===" -ForegroundColor Cyan
    Write-Action1Log "Creating new application package from: $InstallerPath" -Level INFO

    # Get installer file info
    $installerFile = Get-Item $InstallerPath
    $installerExtension = $installerFile.Extension.ToLower()

    # Validate installer type
    if ($installerExtension -notin @('.exe', '.msi')) {
        throw "Unsupported installer type: $installerExtension. Only .exe and .msi files are supported."
    }

    Write-Host "`nAnalyzing installer: $($installerFile.Name)" -ForegroundColor Yellow
    Write-Action1Log "Installer file: $($installerFile.FullName)" -Level DEBUG
    Write-Action1Log "Installer size: $([math]::Round($installerFile.Length / 1MB, 2)) MB" -Level DEBUG

    # Use comprehensive metadata extraction with multiple fallback methods
    Write-Host "Extracting metadata (using multiple extraction methods)..." -ForegroundColor Cyan
    $metadata = Get-InstallerMetadata -Path $installerFile.FullName

    $appName = $metadata.ProductName
    $appVersion = $metadata.ProductVersion
    $publisher = $metadata.Publisher
    $description = $metadata.Description
    $installerType = $metadata.InstallerType.ToLower()

    # Display extracted information
    Write-Host "`n--- Extracted Application Information ---" -ForegroundColor Cyan
    Write-Host "  Application Name: $appName"
    Write-Host "  Version: $appVersion"
    Write-Host "  Publisher/Vendor: $publisher"
    Write-Host "  Description: $description"
    Write-Host "  Installer Type: $installerType"
    Write-Host "  Data Sources: $($metadata.Sources -join ', ')" -ForegroundColor DarkGray

    # Prompt for silent install arguments if not provided
    if (-not $InstallSwitches -and -not $SkipPrompt) {
        Write-Host "`n--- Silent Install Arguments ---" -ForegroundColor Cyan

        if ($installerType -eq 'msi') {
            Write-Host "Default MSI switches: $script:DefaultMsiSwitches (automatically added by Action1)"
            Write-Host "You can add additional switches if needed (e.g., INSTALLDIR=`"C:\Program Files\App`")"
            $InstallSwitches = Read-Host "Additional install switches (press Enter for none)"
        } else {
            Write-Host "Common silent install switches:"
            # Show context-aware suggestions based on detected installer type
            if ($installerType -eq 'inno setup') {
                Write-Host "  /verysilent /norestart - Inno Setup (Recommended for this installer)" -ForegroundColor Green
                Write-Host "  /silent /norestart     - Inno Setup (shows progress)"
                $defaultSwitch = "/verysilent /norestart"
            } elseif ($installerType -eq 'nsis') {
                Write-Host "  /S                     - NSIS silent (Recommended for this installer)" -ForegroundColor Green
                $defaultSwitch = "/S"
            } else {
                Write-Host "  /S or /silent      - Generic silent (NSIS, many others)"
                Write-Host "  /quiet /norestart  - Many installers"
                Write-Host "  /verysilent /norestart - Inno Setup"
                Write-Host "  -q -norestart      - Some installers"
                Write-Host "  --silent           - Some modern installers"
                $defaultSwitch = "/S"
            }
            $InstallSwitches = Read-Host "Install switches [$defaultSwitch]"
            if (-not $InstallSwitches) {
                $InstallSwitches = $defaultSwitch
            }
        }
    } elseif (-not $InstallSwitches -and $SkipPrompt) {
        # Apply smart defaults based on detected installer type
        $InstallSwitches = switch ($installerType) {
            'msi' { "" }
            'inno setup' { "/verysilent /norestart" }
            'nsis' { "/S" }
            default { "/S" }
        }
    }

    # Prompt for uninstall switches if not provided
    if (-not $UninstallSwitches -and -not $SkipPrompt) {
        $defaultUninstall = switch ($installerType) {
            'msi' { "" }
            'inno setup' { "/verysilent /norestart" }
            'nsis' { "/S" }
            default { "/S" }
        }
        $UninstallSwitches = Read-Host "Uninstall switches [$defaultUninstall]"
        if (-not $UninstallSwitches) {
            $UninstallSwitches = $defaultUninstall
        }
    } elseif (-not $UninstallSwitches -and $SkipPrompt) {
        $UninstallSwitches = switch ($installerType) {
            'msi' { "" }
            'inno setup' { "/verysilent /norestart" }
            'nsis' { "/S" }
            default { "/S" }
        }
    }

    # Sanitize names for folder creation
    $sanitizedPublisher = $publisher -replace '[\\/:*?"<>|]', '_' -replace '\s+', '_'
    $sanitizedAppName = $appName -replace '[\\/:*?"<>|]', '_' -replace '\s+', '_'
    $sanitizedVersion = $appVersion -replace '[\\/:*?"<>|]', '_'

    # Create folder structure: /vendor/app/version/
    $packagePath = Join-Path $BasePath $sanitizedPublisher $sanitizedAppName $sanitizedVersion

    Write-Host "`n--- Creating Package Structure ---" -ForegroundColor Cyan
    Write-Host "Package path: $packagePath"
    Write-Action1Log "Creating package folder structure: $packagePath" -Level INFO

    # Create directories
    $directories = @(
        $packagePath,
        (Join-Path $packagePath "installers"),
        (Join-Path $packagePath "scripts"),
        (Join-Path $packagePath "documentation")
    )

    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            Write-Action1Log "Creating directory: $dir" -Level DEBUG
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Host "  Created: $dir" -ForegroundColor Gray
        } else {
            Write-Action1Log "Directory already exists: $dir" -Level WARN
            Write-Host "  Exists: $dir" -ForegroundColor Yellow
        }
    }

    # Copy installer to the installers folder
    $destinationInstaller = Join-Path $packagePath "installers" $installerFile.Name
    Write-Host "`nCopying installer to package..." -ForegroundColor Cyan
    Write-Action1Log "Copying installer from $($installerFile.FullName) to $destinationInstaller" -Level DEBUG
    Copy-Item -Path $installerFile.FullName -Destination $destinationInstaller -Force
    Write-Host "  Copied: $($installerFile.Name)" -ForegroundColor Gray

    # Create manifest
    $manifest = [PSCustomObject]@{
        AppName = $appName
        Publisher = $publisher
        Description = $description
        Version = $appVersion
        CreatedDate = Get-Date -Format "yyyy-MM-dd"
        LastModified = Get-Date -Format "yyyy-MM-dd"
        InstallerType = $installerType
        InstallerFileName = $installerFile.Name
        InstallSwitches = $InstallSwitches
        UninstallSwitches = $UninstallSwitches
        DetectionMethod = @{
            Type = "registry"
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
            SourceFile = $installerFile.Name
            OriginalPath = $installerFile.FullName
        }
    }

    # Save manifest
    $manifestPath = Join-Path $packagePath "manifest.json"
    Write-Action1Log "Creating manifest file: $manifestPath" -Level INFO
    Write-ManifestFile -Manifest $manifest -Path $manifestPath

    # Create README
    $readmeContent = @(
        "# $appName - Action1 Deployment Package",
        "",
        "## Overview",
        "This repository contains the deployment package for $appName.",
        "",
        "**Publisher:** $publisher",
        "**Version:** $appVersion",
        "**Created:** $(Get-Date -Format 'yyyy-MM-dd')",
        "",
        "## Structure",
        "- **installers/** - Application installer files",
        "- **scripts/** - Pre/post installation scripts",
        "- **documentation/** - Additional documentation",
        "- **manifest.json** - Application deployment configuration",
        "",
        "## Installation",
        "**Installer Type:** $installerType",
        "**Install Switches:** $(if ($InstallSwitches) { $InstallSwitches } else { '(default)' })",
        $(if ($installerType -eq 'msi') { "**Note:** Action1 automatically adds: $script:DefaultMsiSwitches" } else { "" }),
        "",
        "## Usage",
        '```powershell',
        "# Deploy to Action1",
        "Deploy-Action1App -ManifestPath `"$manifestPath`"",
        "",
        "# Deploy update to existing application",
        "Deploy-Action1AppUpdate -ManifestPath `"$manifestPath`"",
        '```'
    ) -join "`n"

    $readmePath = Join-Path $packagePath "README.md"
    Set-Content -Path $readmePath -Value $readmeContent -Force
    Write-Action1Log "Created README file: $readmePath" -Level DEBUG

    # Display summary
    Write-Host "`n=== Package Summary ===" -ForegroundColor Green
    Write-Host "Application: $appName v$appVersion"
    Write-Host "Publisher: $publisher"
    Write-Host "Installer: $($installerFile.Name) ($installerType)"
    Write-Host "Install switches: $(if ($InstallSwitches) { $InstallSwitches } else { '(none - using defaults)' })"
    if ($installerType -eq 'msi') {
        Write-Host "  (Action1 will add: $script:DefaultMsiSwitches)"
    }
    Write-Host "Package location: $packagePath"
    Write-Host "`nPackage prepared successfully!" -ForegroundColor Green
    Write-Host "Manifest saved to: $manifestPath" -ForegroundColor Cyan

    Write-Action1Log "Package created successfully at: $packagePath" -Level INFO

    return [PSCustomObject]@{
        Success = $true
        PackagePath = $packagePath
        ManifestPath = $manifestPath
        AppName = $appName
        Version = $appVersion
        Publisher = $publisher
        InstallerType = $installerType
        Manifest = $manifest
    }
}

# TODO: update function to prompt for app info if needed
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

            $orgs = if ($orgsResponse.items) { @($orgsResponse.items) } else { @($orgsResponse) }

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
            return ($version | Expand-NestedJsonAttributes -ExpandFileNames -FormatNested)
        }

        # If specific package requested (list versions)
        if ($PackageId) {
            # Fetch package with all fields to get embedded versions array
            $response = Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId/$PackageId?fields=*" `
                -Method GET

            $versions = if ($response.versions) { @($response.versions) } else { @() }
            return ($versions | Expand-NestedJsonAttributes -ExpandFileNames -FormatNested)
        }

        # Get repos list
        $response = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId`?custom=yes&builtin=no&limit=100" `
            -Method GET

        $repos = if ($response.items) { @($response.items) } else { @($response) }

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

        # Fetch package with all fields to get embedded versions array
        Write-Action1Log "Fetching versions for $($selectedRepo.name)..." -Level INFO
        $packageResponse = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId/$($selectedRepo.id)?fields=*" `
            -Method GET

        # Versions are embedded in the package response when using fields=*
        $versions = if ($packageResponse.versions) {
            @($packageResponse.versions)  # Force array in case of single item
        } else {
            @()
        }

        Write-Action1Log "Found $($versions.Count) version(s)" -Level DEBUG

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
            return ($versions | Expand-NestedJsonAttributes -ExpandFileNames -FormatNested)
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

        return ($versionDetails | Expand-NestedJsonAttributes -ExpandFileNames -FormatNested)
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
        $orgs = if ($response.items) { @($response.items) } else { @($response) }
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

# TODO: Add function Get-Action1Repo
# TODO: Add function Get-Action1PackageVersion
# TODO: Add function Update-Action1AppPackage
# TODO: Add function Update-Action1AppRepo
# TODO: Add function Remove-Action1AppPackage
# TODO: Add function Remove-Action1AppRepo


# Module initialization
Write-Verbose "Action1.Tools module loaded"

# Try to load saved credentials if they exist
$credPath = Join-Path $script:Action1ConfigDir "credentials.json"

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
    'Get-Action1ApiCredentials',
    'Set-Action1LogLevel',
    'Get-Action1LogLevel',
    'Get-Action1Organization',
    'Get-Action1EndpointGroup',
    'New-Action1EndpointGroup',
    'Get-Action1Automation',
    'Copy-Action1Automation'
)
