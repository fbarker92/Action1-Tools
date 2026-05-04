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
