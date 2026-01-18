# Action1 Software Repository

A structured repository for managing and packaging macOS and Windows application releases for deployment through Action1 RMM platform.

## Table of Contents

- [Overview](#overview)
- [Architecture & Technical Decisions](#architecture--technical-decisions)
- [Repository Structure](#repository-structure)
- [Platform Support](#platform-support)
- [Usage Guide](#usage-guide)
- [Current Limitations](#current-limitations)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Future Roadmap](#future-roadmap)

---

## Overview

This repository serves as a centralized software package management system for Action1 RMM deployments. It provides a standardized approach to packaging, versioning, and preparing application releases for distribution to managed endpoints.

### Key Features

- **Automated Packaging**: Interactive build script with tab-completion and fuzzy matching
- **Version Management**: Structured directory layout for multiple application versions
- **Platform Separation**: Distinct workflows for macOS and Windows applications
- **Quality Control**: Template-based approach ensuring consistent package structure
- **Build Artifacts**: Automated ZIP generation with appropriate exclusions

---

## Architecture & Technical Decisions

### 1. Directory Structure Design

**Decision**: Platform-first hierarchy (`<platform>/<application>/<version>`)

**Rationale**: 
- Separates platform-specific build requirements and tooling
- Allows platform-specific scripts (`mac/build.sh`) to operate efficiently
- Simplifies permission management and CI/CD integration
- Mirrors Action1's platform-segregated deployment model

**Alternative Considered**: Application-first (`<application>/<platform>/<version>`) was rejected because it would complicate cross-platform build automation and reduce discoverability.

### 2. Build Script Architecture

**Decision**: Single interactive shell script with intelligent path resolution

**Technical Implementation**:
```bash
# Path resolution priority:
1. Current working directory: ./<App>/<Ver>
2. Repository root fallback: mac/<App>/<Ver>
3. Explicit path via -s flag
```

**Rationale**:
- Provides flexibility for different working contexts
- Interactive mode with tab-completion improves UX
- Fuzzy matching handles case-sensitivity issues
- Non-interactive mode supports CI/CD integration

### 3. Package Contents Strategy

**Decision**: Version folders contain all release artifacts directly

**Why**:
- Action1 requires install.sh and common.sh at ZIP root level
- Simplifies the build process (zip contents directly)
- Reduces packaging errors from nested directory structures
- Clear separation between templates and actual release artifacts

### 4. Version Detection Algorithm

**Decision**: Semantic version parsing with interactive selection

**Implementation**:
- Scans for numeric version patterns (e.g., `2.1`, `1.0.0`)
- Presents highest version as default
- Handles multi-version scenarios gracefully

### 5. File Exclusion Strategy

**Decision**: Hardcoded exclusions for mount points and system files

**Excluded Patterns**:
- `local_mnt/` - Development mount points
- `.DS_Store` - macOS metadata files
- Build artifacts (*.zip, *.dmg, *.pkg) via .gitignore

**Rationale**: Prevents pollution of distribution packages with development artifacts and system-specific files.

---

## Repository Structure

### Recommended Layout

```
action1_software_repository/
├── .gitignore                    # Excludes build artifacts, mount points
├── README.md                     # This file
├── LICENSE                       # GPL-3.0
│
├── mac/                          # macOS platform
│   ├── build.sh                  # Packaging script (executable)
│   ├── dist/                     # Output directory for ZIPs (auto-created)
│   │
│   ├── VirtualBuddy/             # Application name
│   │   ├── 2.1/                  # Version directory
│   │   │   ├── VirtualBuddy.app  # Application bundle
│   │   │   ├── install.sh        # Installation script
│   │   │   ├── common.sh         # Helper functions
│   │   │   └── [other files]
│   │   └── templates/            # Optional: version templates
│   │
│   └── [OtherApp]/
│       └── [version]/
│
├── windows/                      # Windows platform
│   └── microsoft_office_365/
│       └── 16.0.012/
│           ├── Office.xml
│           ├── Office.exe
│           └── [other files]
│
└── templates/                    # Shared templates
    └── mac/
        ├── install.sh.template
        └── common.sh.template
```

### File Requirements by Platform

#### macOS Packages (Required in Version Directory)

1. **`install.sh`** - Main installation script
   - Must handle DMG, PKG, or ZIP setups
   - Receives parameters from Action1 (`-m update`, `-s error`, etc.)
   - Must be executable (`chmod +x`)
   - Line endings: LF only (not CRLF)

2. **`common.sh`** - Helper functions library
   - Utility functions for logging, error handling
   - Sourced by install.sh
   - Must use LF line endings

3. **Application Setup File**
   - Supported formats: `.app`, `.dmg`, `.pkg`, `.zip`
   - Must be compatible with target architecture (Intel/Apple Silicon)

4. **Optional Files**
   - License files, documentation
   - Configuration files
   - Additional resources

#### Windows Packages (Required in Version Directory)

1. **Installer Executable** - `.exe`, `.msi`, or `.msix`
2. **Configuration Files** - XML, INI, or JSON as needed
3. **Optional Files** - Licenses, documentation, dependencies

---

## Platform Support

### macOS

**Supported Package Types**:
- Application bundles (`.app`)
- Disk images (`.dmg`)
- Installer packages (`.pkg`)
- ZIP archives (`.zip`)

**Architecture Support**:
- Intel x86_64
- Apple Silicon (ARM64)
- Universal binaries

**OS Compatibility**: Defined per-application in Action1 console

**Installation Scope**: Per-machine (all users) only

### Windows

**Supported Package Types**:
- Executable installers (`.exe`)
- Windows Installer packages (`.msi`)
- MSIX packages (`.msix`)

**Architecture Support**:
- x86 (32-bit)
- x64 (64-bit)

**Installation Scope**: Per-machine (all users) only

### Linux

**Note**: Linux packages are not currently handled by this repository. They are deployed via Action1's "Deploy Linux Package" script which uses native package managers (apt, yum, dnf).

---

## Usage Guide

### Prerequisites

- Bash shell (macOS, Linux, or WSL on Windows)
- Write permissions in the repository directory
- Application release files from vendor

### Building a macOS Package

#### Method 1: Interactive Mode (Recommended for First-Time Users)

```bash
cd mac
./build.sh
```

The script will prompt you for:
1. **Application name** - Tab-completion available
2. **Version** - Auto-detected from directory structure
3. **Source folder** (if auto-detection fails) - Tab-completion available

#### Method 2: Non-Interactive Mode (CI/CD & Automation)

```bash
# From repository root
mac/build.sh -a VirtualBuddy -v 2.1

# With custom paths
mac/build.sh -a VirtualBuddy -v 2.1 -s ./custom/path -o ./build/output

# From within mac/ directory
cd mac
./build.sh -a VirtualBuddy -v 2.1
```

#### Command-Line Options

```
-a APP    Application name (required)
-v VER    Version string (required)
-s SRC    Explicit source folder path (optional)
          Default: auto-detected from ./<App>/<Ver> or mac/<App>/<Ver>
-o OUT    Output directory (optional)
          Default: mac/dist
-h        Display help message
```

### Adding a New Application

#### Step 1: Create Directory Structure

```bash
# For macOS
mkdir -p mac/MyApp/1.0.0

# For Windows
mkdir -p windows/MyApp/1.0.0
```

#### Step 2: Prepare Installation Scripts (macOS)

Option A: Copy from template
```bash
cp templates/mac/install.sh mac/MyApp/1.0.0/
cp templates/mac/common.sh mac/MyApp/1.0.0/
```

Option B: Copy from similar application
```bash
cp -r mac/VirtualBuddy/2.1/*.sh mac/MyApp/1.0.0/
```

#### Step 3: Customize install.sh

Edit the script to configure:
- `APP_NAME` - Display name in Action1
- `APP_BUNDLE_NAME` - Actual .app bundle name
- `MOUNT_PATH` - DMG mount point (if using DMG)
- Success/error conditions

**Critical**: Ensure LF line endings (not CRLF)
```bash
# Check line endings
file mac/MyApp/1.0.0/install.sh

# Convert if needed (macOS/Linux)
dos2unix mac/MyApp/1.0.0/install.sh
```

#### Step 4: Add Application Files

```bash
# Copy vendor-provided files
cp /path/to/MyApp.dmg mac/MyApp/1.0.0/
# or
cp -r /path/to/MyApp.app mac/MyApp/1.0.0/
```

#### Step 5: Build Package

```bash
mac/build.sh -a MyApp -v 1.0.0
```

Output: `mac/dist/MyApp-1.0.0.zip`

#### Step 6: Upload to Action1

1. Log into Action1 console
2. Navigate to **Software Repository**
3. Click **Add to Repository**
4. Fill in application details:
   - Display name: `MyApp`
   - Version: `1.0.0`
   - OS: Select macOS versions
5. Upload the generated ZIP file
6. Configure installation settings:
   - Silent install switches (e.g., `-s error`)
   - Success exit codes (typically `0`)
   - Reboot requirements
7. Save and deploy to endpoints

---

## Current Limitations

### 1. Platform Coverage

**Limitation**: Windows build automation not implemented

**Impact**: Windows packages must be manually zipped

**Workaround**: 
```bash
cd windows/MyApp/1.0.0
zip -r ../../../MyApp-1.0.0.zip . -x "local_mnt/*" -x ".DS_Store"
```

**Status**: Tracked for future development

### 2. API Integration

**Limitation**: No direct Action1 API integration

**Impact**: Manual upload required via web console

**Workaround**: Use Action1 console for uploads

**Planned**: Automated upload via Action1 API using OAuth2 authentication

### 3. Architecture Detection

**Limitation**: No automatic CPU architecture detection for macOS

**Impact**: Must manually specify Intel vs. Apple Silicon builds in Action1

**Workaround**: Use universal binaries when available, or prepare separate packages

### 4. Version Conflict Resolution

**Limitation**: Build script does not detect version conflicts in Action1 repository

**Impact**: May accidentally overwrite existing versions

**Workaround**: Check Action1 console before uploading

### 5. Dependency Management

**Limitation**: No automatic dependency resolution or bundling

**Impact**: Dependencies must be manually included or deployed separately

**Workaround**: 
- Include all dependencies in version directory
- Document dependency requirements in install.sh comments
- Use Action1 "Additional Actions" for pre/post-install scripts

### 6. Large File Handling

**Limitation**: No support for packages >5GB

**Impact**: Very large applications may fail to upload or deploy

**Workaround**: Compress aggressively, split into multiple packages, or use post-install download scripts

### 7. Network Mount Points

**Limitation**: Build script requires local filesystem access

**Impact**: Cannot build directly from network shares

**Workaround**: Copy files to local directory first

### 8. Parallel Builds

**Limitation**: No concurrent build support

**Impact**: Must build packages sequentially

**Status**: Not prioritized (builds are typically fast)

### 9. Rollback Mechanism

**Limitation**: No built-in version rollback

**Impact**: Must manually deploy previous version if issues occur

**Workaround**: Maintain all version directories in repository

### 10. Testing Framework

**Limitation**: No automated testing of generated packages

**Impact**: Must manually test deployments on sandbox endpoints

**Recommendation**: Always test on non-production endpoints first

---

## Best Practices

### Version Management

1. **Semantic Versioning**: Use semantic version format (major.minor.patch)
   ```
   ✅ 2.1.0, 1.0.5, 3.2.1
   ❌ v2.1, release-2024, latest
   ```

2. **Immutable Versions**: Never modify a version directory after building
   - Create new version directory instead
   - Preserves rollback capability

3. **Version Retention**: Keep at least 2-3 previous versions
   - Enables rapid rollback
   - Supports staggered deployments

### Script Maintenance

1. **Line Endings**: Always use LF (Unix-style)
   ```bash
   # Check before committing
   git ls-files --eol
   
   # Configure git to auto-convert
   git config core.autocrlf input
   ```

2. **Executable Permissions**: Ensure scripts are executable
   ```bash
   chmod +x mac/build.sh
   chmod +x mac/MyApp/1.0.0/install.sh
   ```

3. **Script Validation**: Test scripts on macOS before committing
   ```bash
   bash -n install.sh  # Check syntax
   shellcheck install.sh  # Lint (if available)
   ```

### Repository Hygiene

1. **Build Artifacts**: Never commit build artifacts
   - Verify .gitignore includes: `*.zip`, `*.dmg`, `*.pkg`, `local_mnt/`

2. **Mount Points**: Clean up temporary mount points
   ```bash
   # Add to .gitignore
   echo "local_mnt/" >> .gitignore
   ```

3. **Documentation**: Update comments in install.sh for complex logic

### Testing Strategy

1. **Sandbox Testing**: Always test on sandbox endpoints first
   - Create test automation in Action1
   - Target dedicated test endpoints

2. **Staged Rollout**: Deploy in phases
   - Phase 1: IT department (1-5 endpoints)
   - Phase 2: Pilot group (10-20 endpoints)
   - Phase 3: Full deployment

3. **Monitoring**: Check Action1 automation history for errors
   - Review exit codes
   - Check endpoint logs: `/tmp/action1_*.log`

### Security Considerations

1. **Code Review**: Review vendor-provided scripts before packaging
2. **Integrity Checks**: Verify checksums of downloaded installers
3. **Least Privilege**: Ensure scripts don't request unnecessary permissions
4. **Secrets Management**: Never hardcode API keys or passwords
   - Use Action1's secure parameter passing
   - Leverage Action1 vault for credentials

---

## Troubleshooting

### Common Issues

#### Issue: "Application not found" during build

**Symptoms**:
```
Error: Could not find version directory for VirtualBuddy 2.1
```

**Causes**:
1. Typo in application name (case-sensitive)
2. Running from wrong directory
3. Version directory doesn't exist

**Solutions**:
```bash
# Check exact directory name
ls mac/

# Use explicit path
mac/build.sh -a VirtualBuddy -v 2.1 -s ./mac/VirtualBuddy/2.1

# Use tab-completion in interactive mode
cd mac && ./build.sh
```

#### Issue: "Permission denied" on build.sh

**Symptoms**:
```
bash: ./build.sh: Permission denied
```

**Solution**:
```bash
chmod +x mac/build.sh
./build.sh
```

#### Issue: Installation fails with "bad interpreter"

**Symptoms**: Script fails on Action1-managed endpoint

**Cause**: CRLF line endings (Windows-style)

**Solution**:
```bash
# Check line endings
file mac/MyApp/1.0.0/install.sh

# Convert to LF
dos2unix mac/MyApp/1.0.0/install.sh
# or
sed -i 's/\r$//' mac/MyApp/1.0.0/install.sh

# Rebuild package
mac/build.sh -a MyApp -v 1.0.0
```

#### Issue: Duplicate paths detected

**Symptoms**:
```
Warning: Multiple candidate paths found
```

**Cause**: Running from `mac/` directory creates duplicate path resolution

**Solution**: Recent script versions deduplicate automatically; update build.sh if seeing this error

#### Issue: Package upload fails in Action1

**Possible Causes**:
1. **File too large**: Check if >5GB
2. **Network timeout**: Retry upload
3. **Missing files**: Verify install.sh and common.sh at ZIP root

**Validation**:
```bash
# Check ZIP structure
unzip -l mac/dist/MyApp-1.0.0.zip | head -20

# Should show install.sh at root level:
# Archive:  MyApp-1.0.0.zip
#   Length      Date    Time    Name
# ---------  ---------- -----   ----
#      4567  2024-01-15 10:30   install.sh
#      1234  2024-01-15 10:30   common.sh
#   5678901  2024-01-15 10:30   MyApp.dmg
```

#### Issue: Installation succeeds but app doesn't launch

**Debugging Steps**:

1. Check Action1 endpoint logs:
   ```bash
   # On the endpoint
   cat /tmp/action1_postinstall.log
   ```

2. Verify installation path:
   ```bash
   ls -la /Applications/MyApp.app
   ```

3. Check file permissions:
   ```bash
   # Should be executable
   ls -la /Applications/MyApp.app/Contents/MacOS/MyApp
   ```

4. Test manual installation on sandbox endpoint

### Debug Mode

Enable detailed logging in build.sh:
```bash
# Add to top of script
set -x  # Print commands as they execute
```

Or run with bash debug mode:
```bash
bash -x mac/build.sh -a MyApp -v 1.0.0
```

### Getting Help

1. **Check Logs**: Review Action1 automation history and endpoint logs
2. **Repository Issues**: Submit issues to this GitHub repository
3. **Action1 Support**: 
   - Documentation: https://www.action1.com/documentation/
   - Support portal: https://support.action1.com/

---

## Future Roadmap

### Planned Enhancements

#### 1. Action1 API Integration (High Priority)

**Goal**: Automate package upload directly from build script

**Implementation Plan**:
```bash
mac/build.sh -a MyApp -v 1.0.0 --upload --api-key $ACTION1_API_KEY
```

**Dependencies**:
- OAuth2 authentication implementation
- Action1 API credentials management
- Error handling for API failures

**Timeline**: Q2 2026

#### 2. Windows Build Script (High Priority)

**Goal**: Parity with macOS build tooling

**Features**:
- PowerShell-based build script
- MSI/EXE detection and packaging
- Silent install parameter validation

**Timeline**: Q1 2026

#### 3. CI/CD Integration (Medium Priority)

**Goal**: Automated builds on commit/tag

**Platforms**: 
- GitHub Actions
- GitLab CI
- Jenkins

**Example Workflow**:
```yaml
# .github/workflows/build.yml
on:
  push:
    paths:
      - 'mac/**'
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build packages
        run: |
          for app in mac/*/; do
            mac/build.sh -a $(basename $app) -v $(ls $app | sort -V | tail -1)
          done
```

**Timeline**: Q3 2026

#### 4. Package Validation Framework (Medium Priority)

**Goal**: Automated quality checks before deployment

**Checks**:
- Syntax validation for shell scripts
- Required file presence verification
- Line ending validation
- Size limit checks
- Malware scanning integration

**Timeline**: Q3 2026

#### 5. Version Management Tools (Low Priority)

**Features**:
- Automated version bumping
- Changelog generation
- Release notes templating

**Timeline**: Q4 2026

#### 6. Multi-Architecture Support (Low Priority)

**Goal**: Automated handling of Intel/Apple Silicon variants

**Features**:
- Automatic architecture detection
- Dual-package generation
- Universal binary creation

**Timeline**: Q4 2026

### Community Contributions

We welcome contributions! Please see CONTRIBUTING.md (coming soon) for guidelines.

**Priority Areas for Contributions**:
- Windows build script implementation
- Package validation tools
- Documentation improvements
- Example application packages

---

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

---

## Changelog

### [Unreleased]
- Enhanced README documentation
- Technical decisions documentation
- Comprehensive troubleshooting guide

### [1.0.0] - Initial Release
- macOS build script with interactive and non-interactive modes
- Template directory structure
- Basic .gitignore configuration
- GPL-3.0 license

---

## Acknowledgments

- Action1 Corporation for RMM platform and API documentation
- Contributors to the Action1 community scripts repository
- macOS packaging best practices from Apple Developer Documentation

---

## Contact

For repository-specific questions:
- GitHub Issues: https://github.com/fbarker92/action1_software_repository/issues

For Action1 platform questions:
- Documentation: https://www.action1.com/documentation/
- Support: https://support.action1.com/

---

**Last Updated**: January 2026
