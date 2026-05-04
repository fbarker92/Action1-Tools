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
