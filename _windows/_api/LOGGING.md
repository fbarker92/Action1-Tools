# Logging Guide for Action1AppDeployment Module

## Overview

The Action1AppDeployment module includes a comprehensive, built-in logging system that provides multiple logging levels and optional file output. This allows you to control the verbosity of output and track deployment activities for troubleshooting and auditing.

## Log Levels

The module supports five logging levels, from most verbose to least verbose:

| Level | Description | Use Case |
|-------|-------------|----------|
| **TRACE** | Most verbose logging including all API request/response data | Debugging API issues, seeing exact JSON payloads |
| **DEBUG** | Detailed operational information | Understanding internal module behavior |
| **INFO** | General informational messages (default) | Normal operation tracking |
| **WARN** | Warning messages for potential issues | Identifying configuration problems |
| **ERROR** | Error messages only | Production environments, critical issues only |

## Setting the Log Level

### Basic Usage

```powershell
# Set to INFO level (default)
Set-Action1LogLevel -Level INFO

# Set to DEBUG for more detail
Set-Action1LogLevel -Level DEBUG

# Set to TRACE for maximum verbosity (includes all API responses)
Set-Action1LogLevel -Level TRACE

# Set to ERROR for minimal output
Set-Action1LogLevel -Level ERROR
```

### Logging to a File

```powershell
# Log to a file in addition to console output
Set-Action1LogLevel -Level DEBUG -LogFile "C:\Logs\action1-deployment.log"

# On macOS/Linux
Set-Action1LogLevel -Level DEBUG -LogFile "$HOME/logs/action1-deployment.log"
```

### Check Current Log Level

```powershell
Get-Action1LogLevel

# Output:
# Current log level: DEBUG
# Log file: C:\Logs\action1-deployment.log
```

## Log Output Examples

### TRACE Level
Most verbose - shows everything including API request/response bodies:

```
[2026-01-20 14:23:45.123] [TRACE] [Get-Action1Headers] Generating authentication headers
[2026-01-20 14:23:45.145] [DEBUG] [Get-Action1Headers] Authentication headers generated successfully
[2026-01-20 14:23:45.150] [DEBUG] [Invoke-Action1ApiRequest] Preparing API request: POST https://app.action1.com/api/organizations/org-123/packages
[2026-01-20 14:23:45.152] [TRACE] [Invoke-Action1ApiRequest] Request body
[2026-01-20 14:23:45.152] [TRACE] [Invoke-Action1ApiRequest] DATA: {"name":"7-Zip","version":"23.01","installerType":"msi"}
[2026-01-20 14:23:45.155] [INFO] [Invoke-Action1ApiRequest] Executing API request...
[2026-01-20 14:23:45.789] [INFO] [Invoke-Action1ApiRequest] API request completed successfully in 634ms
[2026-01-20 14:23:45.790] [TRACE] [Invoke-Action1ApiRequest] Response data
[2026-01-20 14:23:45.790] [TRACE] [Invoke-Action1ApiRequest] DATA: {"id":"pkg-456","status":"created","timestamp":"2026-01-20T14:23:45Z"}
```

### DEBUG Level
Detailed operational info without full API payloads:

```
[2026-01-20 14:23:45.123] [DEBUG] [Get-Action1Headers] Authentication headers generated successfully
[2026-01-20 14:23:45.150] [DEBUG] [Invoke-Action1ApiRequest] Preparing API request: POST https://app.action1.com/api/organizations/org-123/packages
[2026-01-20 14:23:45.155] [INFO] [Invoke-Action1ApiRequest] Executing API request...
[2026-01-20 14:23:45.789] [INFO] [Invoke-Action1ApiRequest] API request completed successfully in 634ms
```

### INFO Level (Default)
General progress messages:

```
[2026-01-20 14:23:45.155] [INFO] [Invoke-Action1ApiRequest] Executing API request...
[2026-01-20 14:23:45.789] [INFO] [Invoke-Action1ApiRequest] API request completed successfully in 634ms
[2026-01-20 14:23:46.012] [INFO] [New-Action1AppRepo] Creating new Action1 app repository for: 7-Zip
[2026-01-20 14:23:46.145] [INFO] [New-Action1AppRepo] Repository creation completed successfully
```

## Best Practices

1. **Development**: Use TRACE or DEBUG level
2. **Testing**: Use DEBUG or INFO level with file logging
3. **Production**: Use INFO or WARN level
4. **Troubleshooting**: Temporarily elevate to TRACE level
5. **Automated Tasks**: Use WARN or ERROR with file logging

---

For more information, see the main README.md file.
