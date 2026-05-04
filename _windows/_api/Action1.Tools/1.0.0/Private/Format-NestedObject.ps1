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
