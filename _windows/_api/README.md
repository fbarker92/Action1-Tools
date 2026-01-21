# Action1 App Deployment PowerShell Module

A comprehensive PowerShell module for deploying and managing applications through Action1 RMM platform. Compatible with PowerShell 7.0+ on Windows, macOS, and Linux.

## Features

- 🚀 **Streamlined Deployment**: Deploy applications to Action1 with a single command
- 📦 **Package Management**: Create and manage application packages with manifest files
- 🔄 **Update Management**: Seamlessly deploy updates to existing applications
- 🏗️ **Repository Structure**: Organized folder structure for installers, scripts, and documentation
- 🤖 **Interactive & Non-Interactive**: Supports both interactive prompts and automated workflows
- 🔧 **Smart Defaults**: Automatic detection of installer types with appropriate default switches
- 📝 **Manifest-Driven**: JSON-based configuration for reproducible deployments
- 📊 **Progress Tracking**: Real-time progress bars and spinners for file uploads
- 🔍 **Comprehensive Logging**: Five log levels (TRACE, DEBUG, INFO, WARN, ERROR) with file output
- ⚡ **Chunked Uploads**: Efficient upload of large files with progress tracking

## Installation

### Option 1: Manual Installation

1. Download the module files
2. Copy the `Action1AppDeployment` folder to your PowerShell modules directory:
   - **Windows**: `C:\Users\<YourUsername>\Documents\PowerShell\Modules\`
   - **macOS/Linux**: `~/.local/share/powershell/Modules/`

3. Import the module:
```powershell
Import-Module Action1AppDeployment
```

### Option 2: Install from Local Path

```powershell
# Set the module path
$modulePath = "C:\Path\To\Action1AppDeployment"
Import-Module $modulePath

# Or add to your profile for automatic loading
Add-Content $PROFILE "`nImport-Module '$modulePath'"
```

## Quick Start

### 1. Set API Credentials

```powershell
# Set credentials for current session
Set-Action1ApiCredentials -ApiKey "your-api-key" -Secret "your-secret"

# Or save credentials for future sessions
Set-Action1ApiCredentials -ApiKey "your-api-key" -Secret "your-secret" -SaveToProfile
```

### 2. Test Connection

```powershell
Test-Action1Connection
```

### 3. Create an App Repository

```powershell
# Create a new app repository with examples
New-Action1AppRepo -AppName "7-Zip" -Path "C:\Apps" -IncludeExamples

# This creates:
# C:\Apps\7-Zip\
# ├── installers\          (Place your installer here)
# ├── scripts\             (Optional pre/post install scripts)
# │   ├── pre-install.ps1
# │   └── post-install.ps1
# ├── documentation\       (Additional docs)
# ├── manifest.json        (Configuration file)
# └── README.md
```

### 4. Package Your Application

```powershell
# Interactive mode - prompts for all details
New-Action1AppPackage -ManifestPath "C:\Apps\7-Zip\manifest.json" -Interactive

# Non-interactive mode - uses smart defaults
New-Action1AppPackage -ManifestPath "C:\Apps\7-Zip\manifest.json"
```

### 5. Deploy to Action1

```powershell
# Deploy new application
Deploy-Action1App -ManifestPath "C:\Apps\7-Zip\manifest.json"

# Deploy update to existing application
Deploy-Action1AppUpdate -ManifestPath "C:\Apps\7-Zip\manifest.json"

# Preview deployment without executing
Deploy-Action1App -ManifestPath "C:\Apps\7-Zip\manifest.json" -WhatIf
```

## Command Reference

### Set-Action1ApiCredentials
Configures API credentials for authenticating with Action1.

```powershell
Set-Action1ApiCredentials -ApiKey "key" -Secret "secret" [-SaveToProfile]
```

**Parameters:**
- `ApiKey` - Your Action1 API key
- `Secret` - Your Action1 API secret
- `SaveToProfile` - Save credentials to local file for persistence

### Test-Action1Connection
Validates API credentials and connection to Action1.

```powershell
Test-Action1Connection
```

### New-Action1AppRepo
Creates a new application repository structure.

```powershell
New-Action1AppRepo -AppName <String> [-Path <String>] [-IncludeExamples]
```

**Parameters:**
- `AppName` - Name of the application (required)
- `Path` - Directory where repo will be created (default: current directory)
- `IncludeExamples` - Include example scripts and documentation

**Example:**
```powershell
New-Action1AppRepo -AppName "Google Chrome" -Path "D:\Deployments" -IncludeExamples
```

### New-Action1AppPackage
Prepares an application for deployment by configuring the manifest.

```powershell
New-Action1AppPackage -ManifestPath <String> [-Interactive]
```

**Parameters:**
- `ManifestPath` - Path to manifest.json file (required)
- `Interactive` - Prompt for all configuration options

**Example:**
```powershell
# Interactive packaging with prompts
New-Action1AppPackage -ManifestPath ".\7-Zip\manifest.json" -Interactive

# Quick packaging with defaults
New-Action1AppPackage -ManifestPath ".\7-Zip\manifest.json"
```

**Installation Switches:**
- **MSI files**: Action1 automatically adds `/qn /norestart`
- **EXE files**: You'll be prompted for switches or can use common ones:
  - `/S` or `/silent` - Generic silent install
  - `/quiet /norestart` - Many installers
  - `/verysilent /norestart` - Inno Setup installers
  - `-q -norestart` - Some installers

### Deploy-Action1App
Deploys a new application to Action1.

```powershell
Deploy-Action1App -ManifestPath <String> [-OrganizationId <String>] [-WhatIf]
```

**Parameters:**
- `ManifestPath` - Path to manifest.json file (required)
- `OrganizationId` - Action1 organization ID (optional if in manifest)
- `WhatIf` - Preview deployment without executing

**Example:**
```powershell
# Deploy new app
Deploy-Action1App -ManifestPath ".\7-Zip\manifest.json"

# Preview deployment
Deploy-Action1App -ManifestPath ".\7-Zip\manifest.json" -WhatIf

# Specify organization
Deploy-Action1App -ManifestPath ".\7-Zip\manifest.json" -OrganizationId "org-12345"
```

### Deploy-Action1AppUpdate
Updates an existing application in Action1.

```powershell
Deploy-Action1AppUpdate -ManifestPath <String> [-Force]
```

**Parameters:**
- `ManifestPath` - Path to manifest.json file (required)
- `Force` - Force update even if version hasn't changed

**Example:**
```powershell
# Update existing app
Deploy-Action1AppUpdate -ManifestPath ".\7-Zip\manifest.json"

# Force update
Deploy-Action1AppUpdate -ManifestPath ".\7-Zip\manifest.json" -Force
```

### Get-Action1App
Retrieves information about deployed applications.

```powershell
Get-Action1App -OrganizationId <String> [-PackageId <String>] [-Name <String>]
```

**Parameters:**
- `OrganizationId` - Action1 organization ID (required)
- `PackageId` - Specific package ID to retrieve
- `Name` - Filter by application name

**Examples:**
```powershell
# List all apps
Get-Action1App -OrganizationId "org-12345"

# Get specific app
Get-Action1App -OrganizationId "org-12345" -PackageId "pkg-67890"

# Find apps by name
Get-Action1App -OrganizationId "org-12345" -Name "Chrome"
```

### Remove-Action1App
Removes an application from Action1.

```powershell
Remove-Action1App -OrganizationId <String> -PackageId <String> [-Force]
```

**Parameters:**
- `OrganizationId` - Action1 organization ID (required)
- `PackageId` - Package ID to remove (required)
- `Force` - Skip confirmation prompt

**Example:**
```powershell
# Remove with confirmation
Remove-Action1App -OrganizationId "org-12345" -PackageId "pkg-67890"

# Force remove without confirmation
Remove-Action1App -OrganizationId "org-12345" -PackageId "pkg-67890" -Force
```

## Manifest File Structure

The `manifest.json` file controls all aspects of your application deployment:

```json
{
  "AppName": "7-Zip",
  "Publisher": "Igor Pavlov",
  "Description": "Free and open-source file archiver",
  "Version": "23.01",
  "CreatedDate": "2026-01-20",
  "LastModified": "2026-01-20",
  "InstallerType": "msi",
  "InstallerFileName": "7z2301-x64.msi",
  "InstallSwitches": "",
  "UninstallSwitches": "/qn",
  "DetectionMethod": {
    "Type": "registry",
    "Path": "HKLM:\\Software\\7-Zip",
    "Value": "Version"
  },
  "Requirements": {
    "OSVersion": "",
    "Architecture": "x64",
    "MinDiskSpaceMB": 50,
    "MinMemoryMB": 0
  },
  "Action1Config": {
    "OrganizationId": "org-12345",
    "PackageId": "pkg-67890",
    "PolicyId": "",
    "DeploymentGroup": ""
  },
  "Metadata": {
    "Tags": ["compression", "archiver"],
    "Notes": "Standard installation"
  }
}
```

### Manifest Fields

| Field | Description |
|-------|-------------|
| `AppName` | Application name as it will appear in Action1 |
| `Publisher` | Software publisher/vendor |
| `Version` | Application version number |
| `InstallerType` | Type of installer: `msi`, `exe`, or `powershell` |
| `InstallerFileName` | Name of the installer file in the `installers` folder |
| `InstallSwitches` | Command-line switches for silent installation |
| `UninstallSwitches` | Command-line switches for silent uninstallation |
| `DetectionMethod.Type` | How to detect if installed: `registry`, `file`, or `script` |
| `DetectionMethod.Path` | Registry path, file path, or script path for detection |
| `Requirements.Architecture` | Required CPU architecture: `x86`, `x64`, or `both` |
| `Action1Config.OrganizationId` | Your Action1 organization ID |
| `Action1Config.PackageId` | Package ID (populated after first deployment) |

## Advanced Usage

### Pre/Post Installation Scripts

Add PowerShell scripts to run before or after installation:

**Pre-Install Script** (`scripts/pre-install.ps1`):
```powershell
# Stop services before installation
Stop-Service -Name "MyAppService" -ErrorAction SilentlyContinue

# Backup configuration
Copy-Item "C:\ProgramData\MyApp\config.xml" "C:\Backup\" -Force

# Clean temporary files
Remove-Item "C:\Temp\MyApp\*" -Recurse -Force
```

**Post-Install Script** (`scripts/post-install.ps1`):
```powershell
# Configure application
Set-Content "C:\ProgramData\MyApp\license.key" $licenseKey

# Start services
Start-Service -Name "MyAppService"

# Create shortcuts
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:PUBLIC\Desktop\MyApp.lnk")
$Shortcut.TargetPath = "C:\Program Files\MyApp\MyApp.exe"
$Shortcut.Save()
```

### Custom Detection Scripts

For complex detection logic, use a PowerShell script:

**Detection Script** (`scripts/detect.ps1`):
```powershell
# Check if specific version is installed
$version = Get-ItemProperty "HKLM:\Software\MyApp" -Name "Version" -ErrorAction SilentlyContinue

if ($version.Version -ge "2.0.0") {
    Write-Host "Installed"
    exit 0
} else {
    Write-Host "Not installed or outdated"
    exit 1
}
```

### Automated Deployment Pipeline

Create a deployment pipeline script:

```powershell
# deployment-pipeline.ps1
param(
    [Parameter(Mandatory)]
    [string]$AppPath
)

# Set credentials (use secure method in production)
Set-Action1ApiCredentials -ApiKey $env:ACTION1_API_KEY -Secret $env:ACTION1_SECRET

# Package the app
$manifest = Join-Path $AppPath "manifest.json"
New-Action1AppPackage -ManifestPath $manifest

# Deploy or update
if ((Get-Content $manifest | ConvertFrom-Json).Action1Config.PackageId) {
    Deploy-Action1AppUpdate -ManifestPath $manifest
} else {
    Deploy-Action1App -ManifestPath $manifest
}
```

### Bulk Application Management

Deploy multiple applications:

```powershell
# Get all app manifests
$apps = Get-ChildItem "C:\Apps" -Recurse -Filter "manifest.json"

foreach ($app in $apps) {
    Write-Host "Processing: $($app.Directory.Name)"
    
    # Package
    New-Action1AppPackage -ManifestPath $app.FullName
    
    # Deploy
    Deploy-Action1App -ManifestPath $app.FullName -WhatIf
}
```

## Installer Switch Reference

### Common MSI Switches
- `/qn` - Silent installation with no UI
- `/qb` - Basic UI with progress bar
- `/norestart` - Suppress automatic restart
- `INSTALLDIR="C:\Custom\Path"` - Custom installation directory
- `ALLUSERS=1` - Install for all users

**Action1 automatically adds `/qn /norestart` for MSI files.**

### Common EXE Switches

| Installer Type | Silent Switch | Uninstall Switch |
|---------------|---------------|------------------|
| Inno Setup | `/verysilent /norestart` | `/verysilent /norestart` |
| NSIS | `/S` | `/S` |
| InstallShield | `/s /v"/qn"` | `/s /v"/qn"` |
| Wise | `/s` | `/s` |
| Generic | `/silent /norestart` | `/silent /norestart` |

### Application-Specific Examples

**Google Chrome:**
```json
"InstallSwitches": "/silent /install"
```

**Adobe Reader:**
```json
"InstallSwitches": "/sAll /rs /msi EULA_ACCEPT=YES"
```

**VLC Media Player:**
```json
"InstallSwitches": "/S"
```

**Notepad++:**
```json
"InstallSwitches": "/S"
```

## Troubleshooting

### Progress Bars and Upload Tracking

The module provides real-time progress tracking for file uploads:

#### Features
- **Overall Progress**: Shows total upload progress across all chunks
- **Chunk Progress**: Displays progress of the current chunk being uploaded
- **File Size Display**: Shows uploaded/total in human-readable format (MB/GB)
- **Speed Optimization**: Automatically chunks large files (>10MB) for reliable uploads
- **Visual Feedback**: Color-coded progress bars and spinners

#### Upload Progress Example
```powershell
# When deploying, you'll see:
Uploading chrome-installer.exe (23.5 MB / 45.2 MB)
Chunk 3 of 5
[====================          ] 60%

Current Chunk
[=============================] 100%
```

#### Customizing Upload Behavior
The module automatically handles chunking based on file size:
- Files < 10MB: Direct upload
- Files ≥ 10MB: Chunked upload (5MB chunks by default)

You can see progress demonstrations:
```powershell
# Run the progress demo
.\Examples\ProgressDemo.ps1
```

## Troubleshooting

### Authentication Issues

**Problem**: "Action1 API credentials not set"
```powershell
# Solution: Set credentials
Set-Action1ApiCredentials -ApiKey "your-key" -Secret "your-secret"

# Verify connection
Test-Action1Connection
```

### Installer Not Found

**Problem**: "Installer file not found"
```powershell
# Check installer location
Get-ChildItem "C:\Apps\MyApp\installers"

# Verify manifest points to correct file
Get-Content "C:\Apps\MyApp\manifest.json" | ConvertFrom-Json | 
    Select-Object InstallerFileName
```

### Package Already Exists

**Problem**: Application already deployed
```powershell
# Use update command instead
Deploy-Action1AppUpdate -ManifestPath ".\manifest.json"

# Or force new deployment by clearing PackageId
$manifest = Get-Content ".\manifest.json" | ConvertFrom-Json
$manifest.Action1Config.PackageId = ""
$manifest | ConvertTo-Json -Depth 10 | Set-Content ".\manifest.json"
```

### Silent Install Not Working

**Problem**: Application shows UI during installation

1. Test switches locally:
```powershell
Start-Process "installer.exe" -ArgumentList "/S" -Wait -NoNewWindow
```

2. Check vendor documentation for correct switches
3. Use Process Monitor to verify switches are being applied

## Best Practices

1. **Version Control**: Store manifests and scripts in Git
2. **Testing**: Always use `-WhatIf` before production deployment
3. **Documentation**: Keep deployment notes in the `documentation` folder
4. **Naming**: Use consistent naming: `AppName-Version` (e.g., `7-Zip-23.01`)
5. **Security**: Store API credentials securely, use `-SaveToProfile` carefully
6. **Validation**: Test installations on a test machine before mass deployment
7. **Logging**: Review Action1 deployment logs after each deployment

## Examples

### Example 1: Deploy Google Chrome

```powershell
# Create repository
New-Action1AppRepo -AppName "Google Chrome" -IncludeExamples

# Place installer in .\Google Chrome\installers\
# Edit manifest.json with Chrome-specific details

# Package
New-Action1AppPackage -ManifestPath ".\Google Chrome\manifest.json" -Interactive

# Deploy
Deploy-Action1App -ManifestPath ".\Google Chrome\manifest.json"
```

### Example 2: Update Existing Application

```powershell
# Update version in manifest
$manifest = Get-Content ".\7-Zip\manifest.json" | ConvertFrom-Json
$manifest.Version = "24.01"
$manifest | ConvertTo-Json -Depth 10 | Set-Content ".\7-Zip\manifest.json"

# Place new installer in installers folder
# Update manifest
New-Action1AppPackage -ManifestPath ".\7-Zip\manifest.json"

# Deploy update
Deploy-Action1AppUpdate -ManifestPath ".\7-Zip\manifest.json"
```

### Example 3: List All Deployed Apps

```powershell
$apps = Get-Action1App -OrganizationId "org-12345"
$apps | Format-Table Name, Version, InstallerType, LastModified
```

## Module Information

- **Module Name**: Action1AppDeployment
- **Version**: 1.0.0
- **PowerShell Version**: 7.0+
- **Platforms**: Windows, macOS, Linux
- **Dependencies**: None

## Support

For issues, questions, or contributions:
- Review the troubleshooting section
- Check Action1 API documentation
- Use verbose mode for detailed output: `-Verbose`

## License

Copyright (c) 2026. All rights reserved.

---

**Happy Deploying! 🚀**
