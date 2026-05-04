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
        'INFO'   { 'WARN' }
        'WARN'   { 'ERROR' }
        'ERROR'  { 'DEBUG' }
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
