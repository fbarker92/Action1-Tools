function Start-Action1PackageUpload {
    <#
    .SYNOPSIS
        Uploads a software package file to Action1 Software Repository.

    .DESCRIPTION
        Compatible wrapper for uploading software packages to Action1 using the
        chunked upload protocol. Similar to the official PSAction1 module's
        Start-Action1PackageUpload function.

        Supports configurable chunk sizes and multiple platforms.

    .PARAMETER PackageId
        The software repository package ID to upload to.

    .PARAMETER VersionId
        The version ID to upload the file to.

    .PARAMETER FilePath
        Path to the installer file to upload.

    .PARAMETER Platform
        Target platform. Valid values:
        - Windows_64 (default)
        - Windows_32
        - Windows_ARM64
        - Mac_AppleSilicon
        - Mac_IntelCPU

    .PARAMETER OrganizationId
        Organization ID. If not specified, uses "all" for enterprise-wide.

    .PARAMETER BufferSizeMB
        Size of upload chunks in megabytes. Default is 24MB.
        Minimum is 5MB, maximum is 100MB.

    .EXAMPLE
        Start-Action1PackageUpload -PackageId "pkg123" -VersionId "ver456" -FilePath "C:\installer.msi"
        # Upload with defaults (Windows_64, 24MB chunks)

    .EXAMPLE
        Start-Action1PackageUpload -PackageId "pkg123" -VersionId "ver456" `
            -FilePath "C:\installer.exe" -Platform "Windows_32" -BufferSizeMB 32
        # Upload 32-bit installer with 32MB chunks

    .EXAMPLE
        Start-Action1PackageUpload -PackageId "pkg123" -VersionId "ver456" `
            -FilePath "/path/to/app.pkg" -Platform "Mac_AppleSilicon" `
            -OrganizationId "org789"
        # Upload Mac installer to specific organization
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
        [string]$VersionId,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$FilePath,

        [Parameter()]
        [ValidateSet('Windows_64', 'Windows_32', 'Windows_ARM64', 'Mac_AppleSilicon', 'Mac_IntelCPU')]
        [string]$Platform = 'Windows_64',

        [Parameter()]
        [string]$OrganizationId = 'all',

        [Parameter()]
        [ValidateRange(5, 100)]
        [int]$BufferSizeMB = 24
    )

    try {
        Write-Action1Log "Starting package upload: $FilePath" -Level INFO
        Write-Action1Log "Package: $PackageId, Version: $VersionId, Platform: $Platform" -Level DEBUG

        # Resolve full path
        $fullPath = Resolve-Path $FilePath
        $fileName = Split-Path $fullPath -Leaf
        $fileSize = (Get-Item $fullPath).Length

        Write-Host "`n=== Action1 Package Upload ===" -ForegroundColor Cyan
        Write-Host "File: $fileName" -ForegroundColor White
        Write-Host "Size: $(ConvertTo-FileSize $fileSize)" -ForegroundColor White
        Write-Host "Platform: $Platform" -ForegroundColor White
        Write-Host "Chunk Size: ${BufferSizeMB}MB" -ForegroundColor White

        # Use the existing chunked upload function
        $null = Invoke-Action1SoftwareRepoUpload `
            -FilePath $fullPath `
            -OrganizationId $OrganizationId `
            -PackageId $PackageId `
            -VersionId $VersionId `
            -Platform $Platform `
            -ChunkSizeMB $BufferSizeMB

        Write-Host "`nUpload completed successfully!" -ForegroundColor Green

        return @{
            Success = $true
            PackageId = $PackageId
            VersionId = $VersionId
            FileName = $fileName
            FileSize = $fileSize
            Platform = $Platform
        }
    }
    catch {
        Write-Error "Package upload failed: $($_.Exception.Message)"
        Write-Action1Log "Package upload failed" -Level ERROR -ErrorRecord $_
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}
