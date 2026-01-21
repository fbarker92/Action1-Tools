# Installation Guide for Action1AppDeployment Module

## Prerequisites

- PowerShell 7.0 or higher
- Windows, macOS, or Linux operating system
- Action1 account with API access
- API key and secret from Action1

### Check PowerShell Version

```powershell
$PSVersionTable.PSVersion
```

If you need to install or update PowerShell 7+:
- **Windows**: Download from https://github.com/PowerShell/PowerShell/releases
- **macOS**: `brew install --cask powershell`
- **Linux**: Follow instructions at https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell

## Installation Methods

### Method 1: Install to User Module Directory (Recommended)

1. **Determine your PowerShell modules directory:**

```powershell
$modulePath = if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
    "$env:USERPROFILE\Documents\PowerShell\Modules"
} else {
    "$HOME/.local/share/powershell/Modules"
}
Write-Host "Module path: $modulePath"
```

2. **Create the modules directory if it doesn't exist:**

```powershell
if (-not (Test-Path $modulePath)) {
    New-Item -Path $modulePath -ItemType Directory -Force
}
```

3. **Copy the module files:**

Extract or copy the `Action1AppDeployment` folder to the modules directory:

```powershell
# If you downloaded a zip file, extract it first
# Then copy the entire Action1AppDeployment folder

Copy-Item -Path ".\Action1AppDeployment" -Destination $modulePath -Recurse -Force
```

4. **Verify installation:**

```powershell
Get-Module -ListAvailable Action1AppDeployment
```

5. **Import the module:**

```powershell
Import-Module Action1AppDeployment
```

### Method 2: Install to System Module Directory (All Users)

**Note**: Requires administrator/sudo privileges

1. **Determine system modules directory:**

```powershell
# Windows
$systemPath = "$env:ProgramFiles\PowerShell\Modules"

# macOS/Linux
$systemPath = "/usr/local/share/powershell/Modules"
```

2. **Copy module (as administrator):**

**Windows (PowerShell as Administrator):**
```powershell
Copy-Item -Path ".\Action1AppDeployment" -Destination "$env:ProgramFiles\PowerShell\Modules" -Recurse -Force
```

**macOS/Linux (with sudo):**
```bash
sudo cp -r ./Action1AppDeployment /usr/local/share/powershell/Modules/
```

3. **Verify and import:**

```powershell
Get-Module -ListAvailable Action1AppDeployment
Import-Module Action1AppDeployment
```

### Method 3: Import from Custom Location

If you want to keep the module in a custom location:

```powershell
# Import from current directory
Import-Module .\Action1AppDeployment\Action1AppDeployment.psd1

# Or from any path
Import-Module "C:\MyModules\Action1AppDeployment\Action1AppDeployment.psd1"
```

## Post-Installation Setup

### 1. Auto-Import on PowerShell Startup

Add to your PowerShell profile to auto-load the module:

```powershell
# Open your profile
code $PROFILE
# or
notepad $PROFILE

# Add this line
Import-Module Action1AppDeployment
```

If your profile doesn't exist:

```powershell
New-Item -Path $PROFILE -ItemType File -Force
Add-Content $PROFILE "Import-Module Action1AppDeployment"
```

### 2. Configure API Credentials

```powershell
# Set credentials for current session only
Set-Action1ApiCredentials -ApiKey "your-api-key" -Secret "your-secret"

# Or save credentials for future sessions
Set-Action1ApiCredentials -ApiKey "your-api-key" -Secret "your-secret" -SaveToProfile
```

**Security Note**: Saved credentials are stored in:
- **Windows**: `%LOCALAPPDATA%\Action1AppDeployment\credentials.json`
- **macOS/Linux**: `~/.action1/credentials.json`

For production environments, consider using:
- Azure Key Vault
- Windows Credential Manager
- Environment variables
- Secure secret management systems

### 3. Verify Installation

```powershell
# Test module is loaded
Get-Command -Module Action1AppDeployment

# Test API connection
Test-Action1Connection

# View available commands
Get-Command -Module Action1AppDeployment | Format-Table Name, CommandType
```

## Platform-Specific Notes

### Windows

```powershell
# Check execution policy
Get-ExecutionPolicy

# If needed, set to RemoteSigned or Unrestricted
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### macOS

```bash
# Install PowerShell if not already installed
brew install --cask powershell

# Launch PowerShell
pwsh

# Then follow standard installation steps
```

### Linux

```bash
# Install PowerShell (Ubuntu/Debian example)
sudo apt-get update
sudo apt-get install -y wget apt-transport-https software-properties-common
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y powershell

# Launch PowerShell
pwsh

# Then follow standard installation steps
```

## Troubleshooting

### Module Not Found

```powershell
# Check module paths
$env:PSModulePath -split [IO.Path]::PathSeparator

# Manually add module path if needed
$env:PSModulePath += ";C:\Path\To\Modules"
```

### Cannot Load Module

```powershell
# Remove and reimport
Remove-Module Action1AppDeployment -ErrorAction SilentlyContinue
Import-Module Action1AppDeployment -Force
```

### Execution Policy Errors (Windows)

```powershell
# Check current policy
Get-ExecutionPolicy -List

# Set for current user
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or bypass for single session
pwsh -ExecutionPolicy Bypass
```

### Permission Errors

**Windows**: Run PowerShell as Administrator
**macOS/Linux**: Use `sudo` for system-wide installation

## Updating the Module

### Manual Update

1. Remove old version:
```powershell
Remove-Module Action1AppDeployment -ErrorAction SilentlyContinue
Remove-Item "$modulePath\Action1AppDeployment" -Recurse -Force
```

2. Copy new version:
```powershell
Copy-Item -Path ".\Action1AppDeployment" -Destination $modulePath -Recurse -Force
```

3. Reimport:
```powershell
Import-Module Action1AppDeployment
```

## Uninstallation

```powershell
# Remove module
Remove-Module Action1AppDeployment -ErrorAction SilentlyContinue

# Delete module files
$modulePath = if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
    "$env:USERPROFILE\Documents\PowerShell\Modules\Action1AppDeployment"
} else {
    "$HOME/.local/share/powershell/Modules/Action1AppDeployment"
}
Remove-Item $modulePath -Recurse -Force

# Delete saved credentials (optional)
$credPath = if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
    "$env:LOCALAPPDATA\Action1AppDeployment"
} else {
    "$HOME/.action1"
}
Remove-Item $credPath -Recurse -Force -ErrorAction SilentlyContinue

# Remove from profile (if added)
# Edit $PROFILE and remove the Import-Module line
```

## Next Steps

After installation:

1. **Run the Quick Start guide:**
   ```powershell
   .\Action1AppDeployment\Examples\QuickStart.ps1
   ```

2. **Review examples:**
   ```powershell
   .\Action1AppDeployment\Examples\DeploymentExamples.ps1
   ```

3. **Read the documentation:**
   - README.md - Comprehensive usage guide
   - Get-Help for each command

4. **Create your first deployment:**
   ```powershell
   New-Action1AppRepo -AppName "YourApp" -IncludeExamples
   ```

## Getting Help

```powershell
# List all available commands
Get-Command -Module Action1AppDeployment

# Get detailed help for a command
Get-Help Deploy-Action1App -Full

# Get examples for a command
Get-Help Deploy-Action1App -Examples

# View online help (if available)
Get-Help Deploy-Action1App -Online
```

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review the README.md documentation
3. Use `-Verbose` flag for detailed output
4. Check Action1 API documentation

---

**Installation complete! You're ready to start deploying applications with Action1.**
