function Invoke-Action1MultiFileUpload {
    <#
    .SYNOPSIS
        Uploads multiple files to Action1 software repository with progress tracking.

    .DESCRIPTION
        Uploads multiple installer files (for different architectures) with real-time
        progress tracking for each file and overall progress.

    .PARAMETER Uploads
        Array of upload specifications. Each item should be a hashtable with:
        - FilePath: Path to the file
        - Platform: Platform identifier (Windows_64, Windows_32, etc.)

    .PARAMETER OrganizationId
        The organization ID (or "all" for enterprise-wide).

    .PARAMETER PackageId
        The software repository package ID.

    .PARAMETER VersionId
        The version ID to upload to.

    .PARAMETER ChunkSizeMB
        Size of each upload chunk in megabytes. Default is 24MB.

    .EXAMPLE
        $uploads = @(
            @{ FilePath = "C:\x64\app.msi"; Platform = "Windows_64" }
            @{ FilePath = "C:\x86\app.msi"; Platform = "Windows_32" }
            @{ FilePath = "C:\arm64\app.msi"; Platform = "Windows_ARM64" }
        )
        Invoke-Action1MultiFileUpload -Uploads $uploads `
            -OrganizationId "all" -PackageId "pkg123" -VersionId "ver456"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Uploads,

        [Parameter(Mandatory)]
        [string]$OrganizationId,

        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
        [string]$VersionId,

        [Parameter()]
        [ValidateRange(5, 100)]
        [int]$ChunkSizeMB = 24
    )

    # Platform display helper
    function Get-PlatformDisplayName {
        param([string]$Platform)
        switch ($Platform) {
            'Windows_64' { 'x64' }
            'Windows_32' { 'x86' }
            'Windows_ARM64' { 'ARM64' }
            'Mac_AppleSilicon' { 'Apple Silicon' }
            'Mac_IntelCPU' { 'Intel' }
            default { $Platform }
        }
    }

    $totalFiles = $Uploads.Count
    Write-Action1Log "Starting multi-file upload of $totalFiles file(s)" -Level INFO

    # Calculate total size for overall progress
    $totalSize = 0
    $fileInfos = @()
    foreach ($upload in $Uploads) {
        if (Test-Path $upload.FilePath) {
            $fi = Get-Item $upload.FilePath
            $totalSize += $fi.Length
            $fileInfos += @{
                Platform = $upload.Platform
                FilePath = $upload.FilePath
                Name = $fi.Name
                Size = $fi.Length
            }
        }
    }

    Write-Host "`nUploading $totalFiles file(s) ($(ConvertTo-FileSize -Bytes $totalSize) total):" -ForegroundColor Cyan
    foreach ($fi in $fileInfos) {
        $platformDisplay = Get-PlatformDisplayName $fi.Platform
        Write-Host "  • [$platformDisplay] $($fi.Name) ($(ConvertTo-FileSize -Bytes $fi.Size))" -ForegroundColor White
    }
    Write-Host ""

    $overallStartTime = Get-Date
    $totalBytesUploaded = 0
    $results = @()
    $fileIndex = 0

    foreach ($fi in $fileInfos) {
        $fileIndex++
        $platformDisplay = Get-PlatformDisplayName $fi.Platform

        # Show overall progress header
        $overallPercent = if ($totalSize -gt 0) { [int](($totalBytesUploaded / $totalSize) * 100) } else { 0 }
        $overallElapsed = (Get-Date) - $overallStartTime
        $overallSpeed = if ($overallElapsed.TotalSeconds -gt 0) { $totalBytesUploaded / $overallElapsed.TotalSeconds } else { 0 }
        $overallSpeedDisplay = if ($overallSpeed -gt 0) { ConvertTo-FileSize -Bytes $overallSpeed } else { "-- " }

        Write-Action1Progress `
            -Activity "Overall: $fileIndex of $totalFiles files" `
            -Status "$(ConvertTo-FileSize -Bytes $totalBytesUploaded) / $(ConvertTo-FileSize -Bytes $totalSize) | $overallSpeedDisplay/s" `
            -PercentComplete $overallPercent `
            -Id 0

        Write-Host "[$fileIndex/$totalFiles] [$platformDisplay] $($fi.Name)..." -ForegroundColor Cyan -NoNewline

        # Build overall context for real-time overall progress updates
        $overallContext = @{
            StartTime = $overallStartTime
            PriorBytes = $totalBytesUploaded
            TotalSize = $totalSize
            FileIndex = $fileIndex
            TotalFiles = $totalFiles
        }

        try {
            $result = Invoke-Action1SoftwareRepoUpload `
                -FilePath $fi.FilePath `
                -OrganizationId $OrganizationId `
                -PackageId $PackageId `
                -VersionId $VersionId `
                -Platform $fi.Platform `
                -ChunkSizeMB $ChunkSizeMB `
                -ProgressId 1 `
                -ShowProgress $true `
                -OverallContext $overallContext

            $totalBytesUploaded += $fi.Size

            $results += @{
                Success = $true
                Platform = $fi.Platform
                FileName = $fi.Name
                FileSize = $fi.Size
                Duration = $result.Duration
            }

            # Clear line and show success
            Write-Host "`r[$fileIndex/$totalFiles] [$platformDisplay] $($fi.Name) " -ForegroundColor Green -NoNewline
            Write-Host "✓ $(ConvertTo-FileSize -Bytes $fi.Size)" -ForegroundColor Green
        }
        catch {
            $results += @{
                Success = $false
                Platform = $fi.Platform
                FileName = $fi.Name
                Error = $_.Exception.Message
            }

            Write-Host "`r[$fileIndex/$totalFiles] [$platformDisplay] $($fi.Name) " -ForegroundColor Red -NoNewline
            Write-Host "✗ Failed" -ForegroundColor Red
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor DarkRed
        }
    }

    # Complete overall progress
    Write-Progress -Activity "Overall" -Id 0 -Completed

    # Summary
    $successCount = ($results | Where-Object { $_.Success }).Count
    $failCount = ($results | Where-Object { -not $_.Success }).Count
    $totalDuration = ((Get-Date) - $overallStartTime).TotalSeconds
    $avgSpeed = if ($totalDuration -gt 0) { $totalBytesUploaded / $totalDuration } else { 0 }

    Write-Host ""
    if ($failCount -eq 0) {
        Write-Host "✓ All $successCount upload(s) completed successfully" -ForegroundColor Green
    }
    else {
        Write-Host "⚠ $successCount succeeded, $failCount failed" -ForegroundColor Yellow
    }
    Write-Host "Total time: $([Math]::Round($totalDuration, 1))s | Average speed: $(ConvertTo-FileSize -Bytes $avgSpeed)/s" -ForegroundColor DarkGray

    return $results
}
