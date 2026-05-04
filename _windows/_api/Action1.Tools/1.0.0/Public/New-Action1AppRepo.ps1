function New-Action1AppRepo {
    <#
    .SYNOPSIS
        Creates a new Action1 application repository structure.

    .DESCRIPTION
        Initializes a new directory structure for managing Action1 application deployments
        in Vendor/AppName/Version format. Includes folders for installers, scripts, and
        a manifest file. Optionally creates the software repository in Action1 via API.

        If parameters are not provided, the function will prompt interactively.

    .PARAMETER AppName
        The name of the application. If not provided, will prompt for it.

    .PARAMETER Publisher
        Publisher/vendor name for the application. Required - will prompt if not provided.
        Used for both the folder structure and Action1 API.

    .PARAMETER Version
        Version number. If not provided, will prompt (defaults to "1.0.0").

    .PARAMETER Path
        The base path where the repository should be created. Defaults to current directory.
        The full path will be: Path/Vendor/AppName/Version

    .PARAMETER IncludeExamples
        If specified, includes example pre/post install scripts.

    .PARAMETER CreateInAction1
        If specified, also creates the software repository in Action1 via API.

    .PARAMETER OrganizationId
        Action1 organization ID or "all" for all organizations.
        If not provided, will prompt for scope selection (defaults to "all").

    .PARAMETER Description
        Description for the Action1 software repository.

    .EXAMPLE
        New-Action1AppRepo
        # Interactive mode - prompts for Vendor, AppName, and Version

    .EXAMPLE
        New-Action1AppRepo -Publisher "Microsoft" -AppName "PowerShell" -Version "7.4.0"
        # Creates: ./Microsoft/PowerShell/7.4.0/

    .EXAMPLE
        New-Action1AppRepo -Publisher "7-Zip" -AppName "7-Zip" -Version "23.01" -CreateInAction1
        # Creates local folder and Action1 software repository
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$AppName,

        [Parameter()]
        [string]$Path = (Get-Location).Path,

        [Parameter()]
        [switch]$IncludeExamples,

        [Parameter()]
        [switch]$CreateInAction1,

        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$Publisher,

        [Parameter()]
        [string]$Version
    )

    Write-Host "`n--- New Action1 App Repository ---" -ForegroundColor Cyan

    # Get existing folders for auto-completion suggestions
    $existingVendors = @(Get-ExistingVendors -BasePath $Path)

    # Prompt for required information if not provided (with fuzzy auto-completion)
    if (-not $Publisher) {
        $Publisher = Read-HostWithCompletion `
            -Prompt "Enter Vendor/Publisher" `
            -Suggestions $existingVendors `
            -Required
        if (-not $Publisher) {
            throw "Vendor/Publisher is required"
        }
    }

    # Sanitize vendor for folder lookup (remove punctuation, replace spaces with underscores)
    $sanitizedVendorForLookup = $Publisher -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
    $existingApps = @(Get-ExistingApps -BasePath $Path -Vendor $sanitizedVendorForLookup)

    if (-not $AppName) {
        $AppName = Read-HostWithCompletion `
            -Prompt "Enter Application Name" `
            -Suggestions $existingApps `
            -Required
        if (-not $AppName) {
            throw "Application Name is required"
        }
    }

    # Sanitize app name for folder lookup (remove punctuation, replace spaces with underscores)
    $sanitizedAppForLookup = $AppName -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
    $existingVersions = @(Get-ExistingVersions -BasePath $Path -Vendor $sanitizedVendorForLookup -AppName $sanitizedAppForLookup)

    if (-not $Version) {
        $Version = Read-HostWithCompletion `
            -Prompt "Enter Version" `
            -Suggestions $existingVersions `
            -Default "1.0.0"
    }

    Write-Action1Log "Creating new Action1 app repository" -Level INFO
    Write-Action1Log "Vendor: $Publisher" -Level DEBUG
    Write-Action1Log "App Name: $AppName" -Level DEBUG
    Write-Action1Log "Version: $Version" -Level DEBUG
    Write-Action1Log "Base path: $Path" -Level DEBUG

    # Sanitize names: remove invalid chars and replace spaces with underscores
    $sanitizedVendor = $Publisher -replace '[\\/:*?"<>|]', '_' -replace '\s+', '_'
    $sanitizedAppName = $AppName -replace '[\\/:*?"<>|]', '_' -replace '\s+', '_'
    $sanitizedVersion = $Version -replace '[\\/:*?"<>|]', '_'

    Write-Action1Log "Sanitized vendor: $sanitizedVendor" -Level DEBUG
    Write-Action1Log "Sanitized app name: $sanitizedAppName" -Level DEBUG
    Write-Action1Log "Sanitized version: $sanitizedVersion" -Level DEBUG

    # Build path: Vendor/AppName/Version
    $repoPath = Join-Path $Path $sanitizedVendor $sanitizedAppName $sanitizedVersion
    Write-Action1Log "Repository path: $repoPath" -Level INFO
    
    # Create directory structure
    $directories = @(
        $repoPath,
        (Join-Path $repoPath "installers"),
        (Join-Path $repoPath "scripts"),
        (Join-Path $repoPath "documentation")
    )
    
    Write-Action1Log "Creating directory structure" -Level INFO
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            Write-Action1Log "Creating directory: $dir" -Level DEBUG
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        } else {
            Write-Action1Log "Directory already exists: $dir" -Level WARN
        }
    }
    
    # Create initial manifest with provided parameters
    $manifest = [PSCustomObject]@{
        AppName = $AppName
        Publisher = if ($Publisher) { $Publisher } else { "" }
        Description = if ($Description) { $Description } else { "" }
        Version = $Version
        CreatedDate = Get-Date -Format "yyyy-MM-dd"
        LastModified = Get-Date -Format "yyyy-MM-dd"
        InstallerType = "msi"  # msi, exe, ps1
        InstallerFileName = ""
        InstallSwitches = ""
        UninstallSwitches = ""
        DetectionMethod = @{
            Type = "registry"  # registry, file, script
            Path = ""
            Value = ""
        }
        Requirements = @{
            OSVersion = ""
            Architecture = "x64"
            MinDiskSpaceMB = 0
            MinMemoryMB = 0
        }
        Action1Config = @{
            OrganizationId = if ($OrganizationId) { $OrganizationId } else { "" }
            PackageId = ""
            PolicyId = ""
            DeploymentGroup = ""
        }
        Metadata = @{
            Tags = @()
            Notes = ""
        }
    }
    
    $manifestPath = Join-Path $repoPath "manifest.json"
    Write-ManifestFile -Manifest $manifest -Path $manifestPath
    
    # Create README
    Write-Action1Log "Creating README file" -Level DEBUG
    $readme = @"
# $AppName - Action1 Deployment Package

## Overview
This repository contains the deployment package for $AppName.

## Structure
- **installers/** - Application installer files
- **scripts/** - Pre/post installation scripts
- **documentation/** - Additional documentation
- **manifest.json** - Application deployment configuration

## Usage
1. Place your installer in the `installers/` folder
2. Update `manifest.json` with application details
3. Run ``Package-Action1App -ManifestPath ".\manifest.json"``
4. Deploy using ``Deploy-Action1AppPackage -ManifestPath ".\manifest.json"``

## Deployment Commands
``````powershell
# Package the application
Package-Action1App -ManifestPath ".\manifest.json"

# Deploy new application
Deploy-Action1AppPackage -ManifestPath ".\manifest.json"

# Deploy update to existing application
Deploy-Action1AppUpdate -ManifestPath ".\manifest.json"
``````

Created: $(Get-Date -Format "yyyy-MM-dd")
"@
    
    $readme | Set-Content (Join-Path $repoPath "README.md") -Force
    
    if ($IncludeExamples) {
        Write-Action1Log "Creating example scripts" -Level INFO
        # Create example pre-install script
        $preInstallExample = @"
# Example pre-installation script
# This runs before the main installer

Write-Host "Running pre-installation tasks..."

# Example: Stop a service
# Stop-Service -Name "ServiceName" -ErrorAction SilentlyContinue

# Example: Backup configuration
# Copy-Item "C:\ProgramData\AppConfig" "C:\Backup\AppConfig" -Recurse -Force

Write-Host "Pre-installation complete."
"@
        $preInstallExample | Set-Content (Join-Path $repoPath "scripts" "pre-install.ps1") -Force
        Write-Action1Log "Created pre-install example script" -Level DEBUG
        
        # Create example post-install script
        $postInstallExample = @"
# Example post-installation script
# This runs after the main installer

Write-Host "Running post-installation tasks..."

# Example: Configure application
# New-Item -Path "C:\ProgramData\AppConfig" -ItemType Directory -Force
# Set-Content "C:\ProgramData\AppConfig\settings.cfg" "config=value"

# Example: Start a service
# Start-Service -Name "ServiceName" -ErrorAction SilentlyContinue

Write-Host "Post-installation complete."
"@
        $postInstallExample | Set-Content (Join-Path $repoPath "scripts" "post-install.ps1") -Force
        Write-Action1Log "Created post-install example script" -Level DEBUG
    }

    # Create software repository in Action1 if requested
    $action1PackageId = $null
    if ($CreateInAction1) {
        Write-Action1Log "Creating software repository in Action1" -Level INFO
        Write-Host "`n--- Creating Action1 Software Repository ---" -ForegroundColor Cyan

        # Prompt for organization scope if not provided
        if (-not $OrganizationId) {
            $selectedOrg = Select-Action1Organization -IncludeAll $true
            $OrganizationId = $selectedOrg.Id
        }

        if (-not $Publisher) {
            $Publisher = Read-Host "Enter publisher/vendor (required)"
            if (-not $Publisher) {
                $Publisher = "Unknown"
                Write-Host "Using default vendor: Unknown" -ForegroundColor Yellow
            }
        }

        if (-not $Description) {
            $Description = Read-Host "Enter description (optional, press Enter to skip)"
        }

        # Create the software repository package in Action1
        try {
            $packageData = @{
                name = $AppName
                vendor = $Publisher
                description = if ($Description) { $Description } else { "Software repository for $AppName" }
            }

            Write-Action1Log "Creating software repository package" -Level DEBUG -Data $packageData

            $createResponse = Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId" `
                -Method POST `
                -Body $packageData

            $action1PackageId = $createResponse.id
            Write-Action1Log "Software repository created: $action1PackageId" -Level INFO

            # Update manifest with Action1 config
            $manifest.Action1Config.OrganizationId = $OrganizationId
            $manifest.Action1Config.PackageId = $action1PackageId
            $manifest.Publisher = if ($Publisher) { $Publisher } else { $manifest.Publisher }
            $manifest.Description = if ($Description) { $Description } else { $manifest.Description }
            Write-ManifestFile -Manifest $manifest -Path $manifestPath

            Write-Host "✓ Software repository created in Action1" -ForegroundColor Green
            Write-Host "  Package ID: $action1PackageId" -ForegroundColor Cyan
        }
        catch {
            Write-Action1Log "Failed to create software repository in Action1" -Level ERROR -ErrorRecord $_
            Write-Host "✗ Failed to create Action1 software repository: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  You can create it manually later or retry with -CreateInAction1" -ForegroundColor Yellow
        }
    }

    Write-Action1Log "Repository creation completed successfully" -Level INFO
    Write-Host "`n✓ Action1 app repository created successfully!" -ForegroundColor Green
    Write-Host "  Vendor:   $Publisher" -ForegroundColor White
    Write-Host "  App:      $AppName" -ForegroundColor White
    Write-Host "  Version:  $Version" -ForegroundColor White
    Write-Host "  Location: $repoPath" -ForegroundColor Cyan
    if ($action1PackageId) {
        Write-Host "  Action1 Package ID: $action1PackageId" -ForegroundColor Cyan
    }
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "1. Place your installer in: $(Join-Path $repoPath 'installers')"
    Write-Host "2. Edit manifest.json to configure deployment settings"
    Write-Host "3. Run Deploy-Action1AppPackage to deploy"

    return $repoPath
}
