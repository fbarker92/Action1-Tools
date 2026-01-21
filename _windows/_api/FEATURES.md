# Complete Features Guide

## Action1AppDeployment Module - All Features

This guide covers all features of the Action1AppDeployment PowerShell module.

---

## Table of Contents
1. [Core Functions](#core-functions)
2. [Logging System](#logging-system)
3. [Progress Tracking](#progress-tracking)
4. [Manifest System](#manifest-system)
5. [Upload Features](#upload-features)
6. [Workflow Examples](#workflow-examples)

---

## Core Functions

### 1. Set-Action1ApiCredentials
Configure API authentication.

```powershell
# Basic usage
Set-Action1ApiCredentials -ApiKey "key" -Secret "secret"

# Save for future sessions
Set-Action1ApiCredentials -ApiKey "key" -Secret "secret" -SaveToProfile
```

**Features:**
- Secure credential storage in memory
- Optional persistence to disk
- Cross-platform (Windows/macOS/Linux)

### 2. New-Action1AppRepo
Initialize application repository structure.

```powershell
New-Action1AppRepo -AppName "7-Zip" -Path "C:\Apps" -IncludeExamples
```

**Creates:**
- `/installers` - For installer files
- `/scripts` - Pre/post installation scripts
- `/documentation` - Additional docs
- `manifest.json` - Configuration file
- `README.md` - Documentation

### 3. New-Action1AppPackage
Prepare application for deployment.

```powershell
# Interactive mode
New-Action1AppPackage -ManifestPath ".\manifest.json" -Interactive

# Non-interactive
New-Action1AppPackage -ManifestPath ".\manifest.json"
```

**Features:**
- Interactive prompts for all configuration
- Smart defaults for common installers
- Installer type detection
- Switch recommendations

### 4. Deploy-Action1App
Deploy new application to Action1.

```powershell
Deploy-Action1App -ManifestPath ".\manifest.json"
```

**Process:**
1. Creates package in Action1
2. Uploads installer with progress tracking
3. Uploads pre/post scripts if present
4. Updates manifest with package ID

### 5. Deploy-Action1AppUpdate
Update existing application.

```powershell
Deploy-Action1AppUpdate -ManifestPath ".\manifest.json"
```

**Features:**
- Updates metadata
- Optional installer replacement
- Version tracking

---

## Logging System

### Log Levels

| Level | Verbosity | Use Case |
|-------|-----------|----------|
| TRACE | Maximum | API debugging, see all request/response data |
| DEBUG | High | Detailed operations, troubleshooting |
| INFO | Normal | General progress (default) |
| WARN | Low | Warnings and errors |
| ERROR | Minimal | Errors only |

### Configuration

```powershell
# Set log level
Set-Action1LogLevel -Level DEBUG

# Enable file logging
Set-Action1LogLevel -Level INFO -LogFile "C:\Logs\action1.log"

# Check current level
Get-Action1LogLevel
```

### Log Output Format

```
[2026-01-20 14:23:45.123] [LEVEL] [FunctionName] Message
[2026-01-20 14:23:45.125] [TRACE] [FunctionName] DATA: {...}
```

### Color Coding

- **TRACE**: Gray
- **DEBUG**: Cyan
- **INFO**: White
- **WARN**: Yellow
- **ERROR**: Red

### Examples

#### Development/Troubleshooting
```powershell
Set-Action1LogLevel -Level TRACE -LogFile "C:\Logs\debug.log"
Deploy-Action1App -ManifestPath ".\manifest.json"
```

#### Production
```powershell
Set-Action1LogLevel -Level INFO -LogFile "C:\Logs\prod-$(Get-Date -Format 'yyyyMMdd').log"
```

#### Automated Tasks
```powershell
Set-Action1LogLevel -Level WARN -LogFile "C:\Logs\automation.log"
```

---

## Progress Tracking

### Features

#### 1. Upload Progress Bars
Shows real-time upload progress with:
- Overall upload progress
- Current chunk progress
- File size (uploaded / total)
- Estimated completion

#### 2. Nested Progress
Multiple progress bars for complex operations:
```
Uploading installer.msi (23.5 MB / 45.2 MB)
Chunk 3 of 5
[====================          ] 60%

Current Chunk
[=============================] 100%
```

#### 3. Animated Spinners
For operations without specific progress:
```
Creating package ⠸
```

### Upload Behavior

#### Small Files (< 10MB)
- Direct upload
- Single progress bar
- Fast and simple

#### Large Files (≥ 10MB)
- Chunked upload (5MB chunks)
- Two progress bars (overall + chunk)
- Reliable for large files
- Resumable (future enhancement)

### Demo

```powershell
# See progress tracking in action
.\Examples\ProgressDemo.ps1
```

---

## Manifest System

### Structure

```json
{
  "AppName": "Application Name",
  "Publisher": "Vendor Name",
  "Description": "Application description",
  "Version": "1.0.0",
  "CreatedDate": "2026-01-20",
  "LastModified": "2026-01-20",
  "InstallerType": "msi",
  "InstallerFileName": "installer.msi",
  "InstallSwitches": "",
  "UninstallSwitches": "",
  "DetectionMethod": {
    "Type": "registry",
    "Path": "HKLM:\\Software\\AppName",
    "Value": "Version"
  },
  "Requirements": {
    "OSVersion": "",
    "Architecture": "x64",
    "MinDiskSpaceMB": 100,
    "MinMemoryMB": 2048
  },
  "Action1Config": {
    "OrganizationId": "org-123",
    "PackageId": "pkg-456",
    "PolicyId": "",
    "DeploymentGroup": ""
  },
  "Metadata": {
    "Tags": ["category"],
    "Notes": ""
  }
}
```

### Key Fields

#### InstallerType
- `msi` - Windows Installer
- `exe` - Executable installer
- `ps1` - PowerShell script

#### DetectionMethod.Type
- `registry` - Check registry key/value
- `file` - Check file existence/version
- `script` - Custom PowerShell script

#### Architecture
- `x86` - 32-bit only
- `x64` - 64-bit only
- `both` - Either architecture

---

## Upload Features

### Automatic Chunking

The module automatically handles file uploads based on size:

```powershell
# This is all automatic - no configuration needed
Deploy-Action1App -ManifestPath ".\manifest.json"
```

**How it works:**
1. Module checks file size
2. Files < 10MB: Direct upload
3. Files ≥ 10MB: Chunked upload (5MB chunks)
4. Progress bars show both overall and chunk progress

### Progress Information

During upload you see:
- **File name**: `installer.msi`
- **Size**: `(23.5 MB / 45.2 MB)`
- **Chunk**: `Chunk 3 of 5`
- **Progress**: Visual progress bars
- **Status**: Current operation

### Upload Phases

Each chunk goes through:
1. **Reading** - Loading chunk from disk
2. **Encoding** - Converting to base64
3. **Uploading** - Sending to Action1
4. **Verifying** - Confirming receipt

### Performance

- **Chunking**: Prevents timeouts on large files
- **Encoding**: Efficient base64 conversion
- **Progress**: Minimal performance impact
- **Memory**: Streams large files (doesn't load entire file)

---

## Workflow Examples

### Example 1: New Application Deployment

```powershell
# 1. Setup
Import-Module Action1AppDeployment
Set-Action1ApiCredentials -ApiKey $apiKey -Secret $secret
Set-Action1LogLevel -Level INFO -LogFile "C:\Logs\deployment.log"

# 2. Create repository
$repoPath = New-Action1AppRepo -AppName "Google Chrome" -Path "C:\Apps"

# 3. Copy installer
Copy-Item "C:\Downloads\ChromeSetup.exe" "$repoPath\installers\"

# 4. Package
New-Action1AppPackage -ManifestPath "$repoPath\manifest.json" -Interactive

# 5. Deploy
Deploy-Action1App -ManifestPath "$repoPath\manifest.json"
```

### Example 2: Application Update

```powershell
# 1. Update manifest
$manifest = Get-Content ".\7-Zip\manifest.json" | ConvertFrom-Json
$manifest.Version = "24.01"
$manifest | ConvertTo-Json -Depth 10 | Set-Content ".\7-Zip\manifest.json"

# 2. Copy new installer
Copy-Item "C:\Downloads\7z2401-x64.msi" ".\7-Zip\installers\"

# 3. Package and deploy
New-Action1AppPackage -ManifestPath ".\7-Zip\manifest.json"
Deploy-Action1AppUpdate -ManifestPath ".\7-Zip\manifest.json"
```

### Example 3: Bulk Deployment

```powershell
Set-Action1LogLevel -Level INFO -LogFile "C:\Logs\bulk-$(Get-Date -Format 'yyyyMMdd').log"

$apps = Get-ChildItem "C:\Apps\*\manifest.json"

foreach ($app in $apps) {
    Write-Host "`nDeploying: $($app.Directory.Name)" -ForegroundColor Cyan
    
    try {
        New-Action1AppPackage -ManifestPath $app.FullName
        Deploy-Action1App -ManifestPath $app.FullName
        Write-Host "✓ Success" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Failed: $_" -ForegroundColor Red
    }
}
```

### Example 4: CI/CD Integration

```powershell
# deployment-pipeline.ps1
param(
    [Parameter(Mandatory)]
    [string]$ManifestPath,
    
    [Parameter(Mandatory)]
    [string]$ApiKey,
    
    [Parameter(Mandatory)]
    [string]$Secret
)

# Setup
Import-Module Action1AppDeployment
Set-Action1ApiCredentials -ApiKey $ApiKey -Secret $Secret
Set-Action1LogLevel -Level INFO -LogFile "./deployment.log"

try {
    # Package
    New-Action1AppPackage -ManifestPath $ManifestPath
    
    # Deploy or update
    $manifest = Get-Content $ManifestPath | ConvertFrom-Json
    if ($manifest.Action1Config.PackageId) {
        Deploy-Action1AppUpdate -ManifestPath $ManifestPath
    } else {
        Deploy-Action1App -ManifestPath $ManifestPath
    }
    
    Write-Output "Deployment succeeded"
    exit 0
}
catch {
    Write-Output "Deployment failed: $_"
    Get-Content "./deployment.log" | Select-String "ERROR"
    exit 1
}
```

### Example 5: With Pre/Post Scripts

```powershell
# Create repo with examples
$repoPath = New-Action1AppRepo -AppName "CustomApp" -Path "C:\Apps" -IncludeExamples

# Customize pre-install script
$preScript = @"
# Stop service
Stop-Service "CustomAppService" -Force -ErrorAction SilentlyContinue

# Backup config
Copy-Item "C:\ProgramData\CustomApp" "C:\Backup\CustomApp_`$(Get-Date -Format 'yyyyMMdd')" -Recurse
"@

$preScript | Set-Content "$repoPath\scripts\pre-install.ps1"

# Deploy
New-Action1AppPackage -ManifestPath "$repoPath\manifest.json" -Interactive
Deploy-Action1App -ManifestPath "$repoPath\manifest.json"
```

---

## Best Practices

### 1. Logging
- Use INFO for production
- Use DEBUG when troubleshooting
- Always log to file for auditing
- Rotate logs regularly

### 2. Version Control
- Store manifests in Git
- Track changes to deployment configurations
- Use branches for testing

### 3. Testing
- Test on non-production org first
- Use -WhatIf when available
- Verify detection methods
- Test uninstall procedures

### 4. Documentation
- Keep notes in manifest.json Metadata
- Document custom scripts
- Maintain README in each repo
- Record deployment dates and results

### 5. Organization
- One repo per application
- Consistent naming conventions
- Clear folder structure
- Regular cleanup of old installers

---

## Additional Resources

- **README.md** - Complete usage guide
- **LOGGING.md** - Detailed logging documentation
- **INSTALL.md** - Installation instructions
- **QUICKREF.md** - Quick reference card
- **Examples/** - Sample scripts and scenarios
  - QuickStart.ps1
  - DeploymentExamples.ps1
  - ProgressDemo.ps1
  - LoggingDemo.ps1

---

## Support

For issues or questions:
1. Enable TRACE logging
2. Review log files
3. Check Action1 API documentation
4. Run test deployments
5. Use -WhatIf for dry runs

---

**Version**: 1.0.0
**Last Updated**: 2026-01-20
