# Action1AppDeployment Quick Reference

## Installation
```powershell
# Import module
Import-Module .\Action1AppDeployment

# Or from standard location
Import-Module Action1AppDeployment
```

## Setup
```powershell
# Set API credentials
Set-Action1ApiCredentials -ApiKey "your-key" -Secret "your-secret"

# Test connection
Test-Action1Connection

# Set logging level
Set-Action1LogLevel -Level DEBUG -LogFile "C:\Logs\action1.log"
```

## Create New App Package
```powershell
# Create repository
New-Action1AppRepo -AppName "7-Zip" -Path "C:\Apps" -IncludeExamples

# Package the app (interactive)
New-Action1AppPackage -ManifestPath "C:\Apps\7-Zip\manifest.json" -Interactive

# Deploy
Deploy-Action1App -ManifestPath "C:\Apps\7-Zip\manifest.json"
```

## Update Existing App
```powershell
# Update manifest version and installer
# Then package and deploy update
New-Action1AppPackage -ManifestPath ".\manifest.json"
Deploy-Action1AppUpdate -ManifestPath ".\manifest.json"
```

## Query Apps
```powershell
# List all apps
Get-Action1App -OrganizationId "org-123"

# Get specific app
Get-Action1App -OrganizationId "org-123" -PackageId "pkg-456"

# Search by name
Get-Action1App -OrganizationId "org-123" -Name "Chrome"
```

## Logging Levels
- **TRACE** - Maximum verbosity, includes all API data
- **DEBUG** - Detailed operations
- **INFO** - General progress (default)
- **WARN** - Warnings only
- **ERROR** - Errors only

```powershell
Set-Action1LogLevel -Level TRACE  # See everything
Set-Action1LogLevel -Level INFO   # Normal use
Set-Action1LogLevel -Level ERROR  # Quiet mode
```

## Common Workflows

### Deploy New Application
```powershell
$appName = "Google Chrome"
$repoPath = New-Action1AppRepo -AppName $appName -Path "C:\Deployments"

# Copy installer to $repoPath\installers\
New-Action1AppPackage -ManifestPath "$repoPath\manifest.json" -Interactive
Deploy-Action1App -ManifestPath "$repoPath\manifest.json"
```

### Bulk Deployment
```powershell
Get-ChildItem "C:\Apps\*\manifest.json" | ForEach-Object {
    Write-Host "Deploying: $($_.Directory.Name)"
    New-Action1AppPackage -ManifestPath $_.FullName
    Deploy-Action1App -ManifestPath $_.FullName
}
```

### Update with Logging
```powershell
Set-Action1LogLevel -Level DEBUG -LogFile "C:\Logs\update.log"
Deploy-Action1AppUpdate -ManifestPath ".\manifest.json"
```

## Installer Switches

### MSI (Auto-added by Action1)
- Action1 automatically adds: `/qn /norestart`
- Just specify additional switches if needed

### EXE Common Switches
- Inno Setup: `/VERYSILENT /NORESTART`
- NSIS: `/S`
- InstallShield: `/s /v"/qn"`
- Generic: `/silent /norestart`

## Manifest Structure
```json
{
  "AppName": "Application Name",
  "Version": "1.0.0",
  "InstallerType": "msi",
  "InstallerFileName": "installer.msi",
  "InstallSwitches": "",
  "Action1Config": {
    "OrganizationId": "org-123",
    "PackageId": "pkg-456"
  }
}
```

## Help
```powershell
# Get help for any command
Get-Help Deploy-Action1App -Full
Get-Help Set-Action1LogLevel -Examples

# List all commands
Get-Command -Module Action1AppDeployment
```

## Troubleshooting
```powershell
# Enable trace logging
Set-Action1LogLevel -Level TRACE -LogFile "C:\Logs\debug.log"

# Test connection
Test-Action1Connection

# Review logs
Get-Content "C:\Logs\debug.log" | Select-String "ERROR|WARN"
```
