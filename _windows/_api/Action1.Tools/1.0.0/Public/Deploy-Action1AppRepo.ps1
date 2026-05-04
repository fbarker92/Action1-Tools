function Deploy-Action1AppRepo {
    <#
    .SYNOPSIS
        Deploys an entire application repository to Action1 Software Repository.

    .DESCRIPTION
        Deploys all package versions from a local application repository to Action1.
        This function iterates through all version folders in an app repo and deploys
        each one using Deploy-Action1AppPackage.

    .PARAMETER Path
        Path to the application repository folder (vendor/app level).
        This should be the folder containing version subfolders.

    .PARAMETER Vendor
        Vendor/Publisher name. Used with BasePath to construct the app repo path.

    .PARAMETER AppName
        Application name. Used with BasePath and Vendor to construct the app repo path.

    .PARAMETER BasePath
        Base path where vendor folders are located. Defaults to current directory.
        Used with Vendor and AppName parameters.

    .PARAMETER OrganizationId
        Action1 organization ID. If not specified, prompts for selection once
        and uses the same organization for all versions.

    .PARAMETER DryRun
        Shows what would be deployed without actually deploying.

    .PARAMETER VersionFilter
        Optional filter to deploy only specific versions. Supports wildcards.
        Example: "1.*" to deploy only 1.x versions.

    .EXAMPLE
        Deploy-Action1AppRepo -Path ".\Microsoft\PowerShell"
        # Deploys all versions of PowerShell from the specified path

    .EXAMPLE
        Deploy-Action1AppRepo -Vendor "Microsoft" -AppName "PowerShell" -OrganizationId "all"
        # Deploys all versions to all organizations

    .EXAMPLE
        Deploy-Action1AppRepo -Path ".\7-Zip\7-Zip" -VersionFilter "23.*" -DryRun
        # Preview deployment of only version 23.x packages
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByPath')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByPath', Position = 0)]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Vendor,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$AppName,

        [Parameter(ParameterSetName = 'ByName')]
        [string]$BasePath = (Get-Location).Path,

        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [string]$VersionFilter
    )

    Write-Host "`n=== Action1 Application Repository Deployment ===" -ForegroundColor Cyan

    try {
        # Get app repo info
        $repoInfoParams = @{}
        if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
            $repoInfoParams['Path'] = $Path
        }
        else {
            $repoInfoParams['Vendor'] = $Vendor
            $repoInfoParams['AppName'] = $AppName
            $repoInfoParams['BasePath'] = $BasePath
        }

        $repoInfo = Get-Action1AppRepo @repoInfoParams

        if (-not $repoInfo -or $repoInfo.VersionCount -eq 0) {
            throw "No versions found in application repository"
        }

        # Filter versions if specified
        $versionsToDeploy = $repoInfo.Versions
        if ($VersionFilter) {
            $versionsToDeploy = $versionsToDeploy | Where-Object { $_.Version -like $VersionFilter }
            Write-Host "Filtered to $($versionsToDeploy.Count) version(s) matching '$VersionFilter'" -ForegroundColor Yellow
        }

        if ($versionsToDeploy.Count -eq 0) {
            throw "No versions match the specified filter"
        }

        # Get organization ID once for all deployments
        if (-not $OrganizationId) {
            $selectedOrg = Select-Action1Organization -IncludeAll $true
            $OrganizationId = $selectedOrg.Id
        }

        Write-Host "`nDeploying $($versionsToDeploy.Count) version(s) to organization: $OrganizationId" -ForegroundColor Cyan

        # Check for -WhatIf or -DryRun
        $isWhatIf = $WhatIfPreference -or $DryRun

        if ($isWhatIf) {
            Write-Host "`n=== Deployment Preview (WhatIf/DryRun) ===" -ForegroundColor Yellow
            Write-Host "Would deploy the following versions:"
            foreach ($ver in $versionsToDeploy) {
                $archInfo = if ($ver.Architectures) { " [$($ver.Architectures)]" } else { "" }
                Write-Host "  - v$($ver.Version)$archInfo"
            }
            return @{
                Success = $true
                DryRun = $true
                VersionCount = $versionsToDeploy.Count
                Versions = $versionsToDeploy.Version
            }
        }

        # Deploy each version
        $results = @()
        $successCount = 0
        $failCount = 0

        foreach ($ver in $versionsToDeploy) {
            Write-Host "`n--- Deploying v$($ver.Version) ---" -ForegroundColor Yellow

            try {
                $deployResult = Deploy-Action1AppPackage `
                    -ManifestPath $ver.ManifestPath `
                    -OrganizationId $OrganizationId

                if ($deployResult.Success) {
                    $successCount++
                    $results += @{
                        Version = $ver.Version
                        Success = $true
                        RepositoryId = $deployResult.RepositoryId
                        VersionId = $deployResult.VersionId
                    }
                }
                else {
                    $failCount++
                    $results += @{
                        Version = $ver.Version
                        Success = $false
                        Error = $deployResult.Error
                    }
                }
            }
            catch {
                $failCount++
                $results += @{
                    Version = $ver.Version
                    Success = $false
                    Error = $_.Exception.Message
                }
                Write-Error "Failed to deploy v$($ver.Version): $($_.Exception.Message)"
            }
        }

        # Summary
        Write-Host "`n=== Deployment Summary ===" -ForegroundColor Cyan
        Write-Host "Application: $($repoInfo.AppName)" -ForegroundColor Green
        Write-Host "Publisher: $($repoInfo.Publisher)" -ForegroundColor Green
        Write-Host "Total Versions: $($versionsToDeploy.Count)"
        Write-Host "Successful: $successCount" -ForegroundColor Green
        if ($failCount -gt 0) {
            Write-Host "Failed: $failCount" -ForegroundColor Red
        }

        return @{
            Success = ($failCount -eq 0)
            AppName = $repoInfo.AppName
            Publisher = $repoInfo.Publisher
            OrganizationId = $OrganizationId
            TotalVersions = $versionsToDeploy.Count
            SuccessCount = $successCount
            FailCount = $failCount
            Results = $results
        }
    }
    catch {
        Write-Error "Repository deployment failed: $($_.Exception.Message)"
        Write-Action1Log "Repository deployment failed" -Level ERROR -ErrorRecord $_
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}
