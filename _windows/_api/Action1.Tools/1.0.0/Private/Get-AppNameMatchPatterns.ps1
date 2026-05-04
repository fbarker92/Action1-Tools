function Get-AppNameMatchPatterns {
    <#
    .SYNOPSIS
        Generates regex patterns for matching application display names.

    .DESCRIPTION
        Creates two patterns for the Action1 app_name_match field:
        - Specific: Matches the exact app name with version placeholder
        - Broad: Matches variations of the app name

    .PARAMETER AppName
        The application name to generate patterns for.

    .OUTPUTS
        Returns a hashtable with Specific and Broad regex patterns.

    .EXAMPLE
        Get-AppNameMatchPatterns -AppName "PowerShell 7 Preview"
        # Returns: @{ Specific = "^PowerShell 7 Preview.*$"; Broad = "^PowerShell.*Preview.*$" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName
    )

    # Escape regex special characters in the app name
    $escapedName = [regex]::Escape($AppName)

    # Specific pattern: exact name followed by optional version info
    $specificPattern = "^$escapedName.*`$"

    # Broad pattern: key words from the app name with wildcards between
    # Extract significant words (3+ characters, not common words)
    $commonWords = @('the', 'and', 'for', 'with', 'from')
    $words = $AppName -split '\s+' | Where-Object {
        $_.Length -ge 3 -and $_ -notin $commonWords
    }

    if ($words.Count -gt 0) {
        # Join words with .* to create a broad match
        $escapedWords = $words | ForEach-Object { [regex]::Escape($_) }
        $broadPattern = "^" + ($escapedWords -join '.*') + ".*`$"
    }
    else {
        # Fallback to escaped name
        $broadPattern = "^$escapedName.*`$"
    }

    return @{
        Specific = $specificPattern
        Broad    = $broadPattern
    }
}
