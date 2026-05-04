function Deploy-Action1AppUpdate {
    <#
    .SYNOPSIS
        Deploys an update to an existing Action1 application.
    
    .DESCRIPTION
        Updates an existing application package in Action1 with a new version.
    
    .PARAMETER ManifestPath
        Path to the manifest.json file.
    
    .PARAMETER Force
        Forces the update even if version hasn't changed.
    
    .EXAMPLE
        Deploy-Action1AppUpdate -ManifestPath ".\7-Zip\manifest.json"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,
        
        [Parameter()]
        [switch]$Force
    )
    
    Write-Host "`n=== Action1 Application Update ===" -ForegroundColor Cyan
    
    # Load manifest
    $manifest = Read-ManifestFile -Path $ManifestPath
    
    if (-not $manifest.Action1Config.PackageId) {
        Write-Error "No existing package found in manifest. Use Deploy-Action1AppPackage for initial deployment."
        return
    }
    
    $packageId = $manifest.Action1Config.PackageId
    $orgId = $manifest.Action1Config.OrganizationId
    $repoPath = Split-Path $ManifestPath -Parent
    
    Write-Host "Updating package: $packageId"
    Write-Host "New version: $($manifest.Version)"
    
    if ($PSCmdlet.ShouldProcess($manifest.AppName, "Update application")) {
        try {
            # Update package metadata
            Write-Host "Updating package metadata..."
            
            $updateData = @{
                version = $manifest.Version
                description = $manifest.Description
                installParameters = $manifest.InstallSwitches
                uninstallParameters = $manifest.UninstallSwitches
                lastModified = Get-Date -Format "o"
            }
            
            Invoke-Action1ApiRequest `
                -Endpoint "organizations/$orgId/packages/$packageId" `
                -Method PATCH `
                -Body $updateData
            
            Write-Host "✓ Package metadata updated" -ForegroundColor Green
            
            # Upload new installer if changed
            $installerPath = Join-Path $repoPath "installers" $manifest.InstallerFileName
            if (Test-Path $installerPath) {
                $uploadNew = Read-Host "Upload new installer file? (y/N)"
                if ($uploadNew -eq 'y' -or $uploadNew -eq 'Y') {
                    Write-Host "Uploading updated installer..."
                    Write-Action1Log "Starting installer update upload" -Level INFO
                    
                    $fileSize = (Get-Item $installerPath).Length
                    Write-Action1Log "Installer size: $(ConvertTo-FileSize -Bytes $fileSize)" -Level DEBUG
                    
                    # Use progress-enabled upload
                    Invoke-Action1FileUpload `
                        -FilePath $installerPath `
                        -Endpoint "organizations/$orgId/packages/$packageId/upload" `
                        -ChunkSizeMB 5
                    
                    Write-Host "✓ Installer updated" -ForegroundColor Green
                    Write-Action1Log "Installer update completed" -Level INFO
                }
            }
            
            Write-Host "`n✓ Update completed successfully!" -ForegroundColor Green
            
            return @{
                Success = $true
                PackageId = $packageId
                Version = $manifest.Version
            }
        }
        catch {
            Write-Error "Update failed: $($_.Exception.Message)"
            return @{
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
}
