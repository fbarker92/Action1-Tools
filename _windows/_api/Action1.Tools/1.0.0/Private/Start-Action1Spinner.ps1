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
