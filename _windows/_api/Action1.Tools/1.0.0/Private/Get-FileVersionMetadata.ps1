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
