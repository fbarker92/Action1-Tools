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
