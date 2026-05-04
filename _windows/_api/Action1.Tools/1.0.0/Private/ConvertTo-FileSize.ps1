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
