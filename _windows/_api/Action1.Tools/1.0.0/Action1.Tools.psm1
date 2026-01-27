#Requires -Version 7.0

# Module-level variables
$script:Action1Region = $null
$script:Action1BaseUri = $null
$script:Action1ClientId = $null
$script:Action1ClientSecret = $null
$script:Action1AccessToken = $null
$script:Action1TokenExpiry = $null

# Region to API URL mapping
$script:Action1RegionUrls = @{
    'NorthAmerica' = 'https://app.action1.com/api/3.0'
    'Europe'       = 'https://app.eu.action1.com/api/3.0'
    'Australia'    = 'https://app.au.action1.com/api/3.0'
}
$script:DefaultMsiSwitches = "/qn /norestart"
$script:LogLevel = "SILENT"
$script:LogFilePath = $null

# Cross-platform configuration directory path
$script:Action1ConfigDir = if ($IsWindows) {
    Join-Path $env:LOCALAPPDATA "Action1.Tools"
} elseif ($IsMacOS) {
    Join-Path $HOME ".action1"
} else {
    # Linux - follow XDG spec
    $xdgConfig = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME ".config" }
    Join-Path $xdgConfig "action1"
}
$script:LogLevels = @{

    SILENT = 0
    INFO = 1
    WARN = 2
    ERROR = 3
    DEBUG = 4
    TRACE = 5

}

#region Helper Functions

function Read-HostWithCompletion {
    <#
    .SYNOPSIS
        Read-Host with real-time tab auto-completion support.

    .DESCRIPTION
        Provides an interactive prompt that supports tab completion against a list
        of suggestions. Press Tab to cycle through matches, Enter to confirm.
        Falls back to numbered selection if tab completion is not available.

    .PARAMETER Prompt
        The prompt text to display.

    .PARAMETER Suggestions
        Array of strings to use for auto-completion.

    .PARAMETER Default
        Default value if user presses Enter without input.

    .PARAMETER Required
        If true, will keep prompting until a value is provided.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter()]
        [string[]]$Suggestions = @(),

        [Parameter()]
        [string]$Default,

        [Parameter()]
        [switch]$Required
    )

    # Show numbered suggestions for easy selection
    if ($Suggestions.Count -gt 0) {
        Write-Host "  Available options:" -ForegroundColor White
        Write-Host "    [0] Create new" -ForegroundColor White
        for ($i = 0; $i -lt $Suggestions.Count; $i++) {
            Write-Host "    [$($i + 1)] $($Suggestions[$i])" -ForegroundColor White
        }
        Write-Host "  (Enter number, type name, or Tab to cycle)" -ForegroundColor White
    }

    do {
        # Build and display prompt
        $promptText = $Prompt
        if ($Default) {
            $promptText = "$Prompt (default: $Default)"
        }
        Write-Host "${promptText}: " -NoNewline

        $currentInput = ""
        $tabIndex = -1
        $tabMatches = @()

        while ($true) {
            # Try to read key - use $host.UI.RawUI on macOS if available
            try {
                $key = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            catch {
                # Fallback to Console.ReadKey
                $key = [Console]::ReadKey($true)
            }

            # Detect key type - check both Key enum and KeyChar for cross-platform support
            $keyChar = $key.Character
            if (-not $keyChar) { $keyChar = $key.KeyChar }

            $virtualKey = $key.VirtualKeyCode
            $isTab = ($key.Key -eq 'Tab') -or ($keyChar -eq "`t") -or ($virtualKey -eq 9)
            $isEnter = ($key.Key -eq 'Enter') -or ($keyChar -eq "`r") -or ($keyChar -eq "`n") -or ($virtualKey -eq 13)
            $isBackspace = ($key.Key -eq 'Backspace') -or ($keyChar -eq [char]8) -or ($keyChar -eq [char]127) -or ($virtualKey -eq 8)
            $isEscape = ($key.Key -eq 'Escape') -or ($keyChar -eq [char]27) -or ($virtualKey -eq 27)

            if ($isEnter) {
                Write-Host ""  # New line

                # Check if input is a number selecting from suggestions
                if ($Suggestions.Count -gt 0 -and $currentInput -match '^\d+$') {
                    $idx = [int]$currentInput

                    # Option 0 = Create new (prompt for name)
                    if ($idx -eq 0) {
                        Write-Host "  Enter new name: " -NoNewline
                        $newName = Read-Host
                        if ($newName) {
                            return $newName
                        }
                        # If empty and required, break to re-prompt
                        if ($Required) {
                            Write-Host "  This field is required." -ForegroundColor Yellow
                            break
                        }
                        return $newName
                    }

                    # Options 1+ = Select from suggestions
                    $idx = $idx - 1
                    if ($idx -ge 0 -and $idx -lt $Suggestions.Count) {
                        return $Suggestions[$idx]
                    }
                }

                # If empty, use default
                if (-not $currentInput -and $Default) {
                    return $Default
                }

                # If empty and required, break to re-prompt
                if (-not $currentInput -and $Required) {
                    Write-Host "  This field is required." -ForegroundColor Yellow
                    break
                }

                return $currentInput
            }
            elseif ($isTab) {
                if ($Suggestions.Count -eq 0) { continue }

                # Find matches on first Tab press
                if ($tabIndex -eq -1) {
                    $tabMatches = @($Suggestions | Where-Object { $_ -like "$currentInput*" })
                    if ($tabMatches.Count -eq 0) {
                        $tabMatches = @($Suggestions | Where-Object { $_ -like "*$currentInput*" })
                    }
                    if ($tabMatches.Count -eq 0) {
                        $tabMatches = @($Suggestions)
                    }
                }

                if ($tabMatches.Count -gt 0) {
                    $tabIndex = ($tabIndex + 1) % $tabMatches.Count

                    # Clear and replace with match
                    Write-Host ("`b" * $currentInput.Length) -NoNewline
                    Write-Host (" " * $currentInput.Length) -NoNewline
                    Write-Host ("`b" * $currentInput.Length) -NoNewline

                    $currentInput = $tabMatches[$tabIndex]
                    Write-Host $currentInput -NoNewline -ForegroundColor Cyan
                }
            }
            elseif ($isBackspace) {
                if ($currentInput.Length -gt 0) {
                    $currentInput = $currentInput.Substring(0, $currentInput.Length - 1)
                    Write-Host "`b `b" -NoNewline
                    $tabIndex = -1
                }
            }
            elseif ($isEscape) {
                Write-Host ("`b" * $currentInput.Length) -NoNewline
                Write-Host (" " * $currentInput.Length) -NoNewline
                Write-Host ("`b" * $currentInput.Length) -NoNewline
                $currentInput = ""
                $tabIndex = -1
            }
            else {
                $char = $keyChar
                if ($char -and ([char]::IsLetterOrDigit($char) -or $char -eq ' ' -or $char -eq '-' -or $char -eq '_' -or $char -eq '.')) {
                    $currentInput += $char
                    Write-Host $char -NoNewline
                    $tabIndex = -1
                }
            }

            if ($isEnter) { break }
        }
    } while ($Required -and -not $currentInput)

    return $currentInput
}

function Read-HostWithFileCompletion {
    <#
    .SYNOPSIS
        Read-Host with real-time file path tab auto-completion.

    .DESCRIPTION
        Provides an interactive prompt that supports tab completion for file paths.
        Press Tab to cycle through matching files/folders, Enter to confirm.

    .PARAMETER Prompt
        The prompt text to display.

    .PARAMETER Filter
        File extension filter (e.g., "*.msi", "*.exe"). Defaults to all files.

    .PARAMETER BasePath
        Base path for relative path resolution. Defaults to current directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter()]
        [string]$Filter = "*",

        [Parameter()]
        [string]$BasePath = (Get-Location).Path
    )

    Write-Host "  (Tab to complete file paths, Enter to confirm)" -ForegroundColor DarkGray
    Write-Host "${Prompt}: " -NoNewline

    $currentInput = ""
    $tabIndex = -1
    $tabMatches = @()
    $lastTabInput = ""

    while ($true) {
        # Try to read key - use $host.UI.RawUI on macOS if available
        try {
            $key = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
        catch {
            # Fallback to Console.ReadKey
            $key = [Console]::ReadKey($true)
        }

        # Detect key type - check both Key enum and KeyChar for cross-platform support
        $keyChar = $key.Character
        if (-not $keyChar) { $keyChar = $key.KeyChar }

        $virtualKey = $key.VirtualKeyCode
        $isTab = ($key.Key -eq 'Tab') -or ($keyChar -eq "`t") -or ($virtualKey -eq 9)
        $isEnter = ($key.Key -eq 'Enter') -or ($keyChar -eq "`r") -or ($keyChar -eq "`n") -or ($virtualKey -eq 13)
        $isBackspace = ($key.Key -eq 'Backspace') -or ($keyChar -eq [char]8) -or ($keyChar -eq [char]127) -or ($virtualKey -eq 8)
        $isEscape = ($key.Key -eq 'Escape') -or ($keyChar -eq [char]27) -or ($virtualKey -eq 27)

        if ($isEnter) {
            Write-Host ""  # New line

            if (-not $currentInput) {
                return ""
            }

            # Resolve relative path to absolute
            if (-not [System.IO.Path]::IsPathRooted($currentInput)) {
                $resolvedPath = Join-Path $BasePath $currentInput
            } else {
                $resolvedPath = $currentInput
            }

            # Normalize the path
            try {
                $resolvedPath = [System.IO.Path]::GetFullPath($resolvedPath)
            } catch {
                # Keep as-is if resolution fails
            }

            return $resolvedPath
        }
        elseif ($isTab) {
            # Build path for completion
            $searchPath = $currentInput

            # Resolve relative paths
            if (-not [System.IO.Path]::IsPathRooted($searchPath)) {
                $searchPath = Join-Path $BasePath $currentInput
            }

            # Check if input changed since last Tab
            if ($currentInput -ne $lastTabInput) {
                $tabIndex = -1
                $lastTabInput = $currentInput

                # Determine directory and file pattern
                $parentDir = Split-Path $searchPath -Parent
                $filePattern = Split-Path $searchPath -Leaf

                if (-not $parentDir) {
                    $parentDir = $BasePath
                }

                # Get matches
                if (Test-Path $parentDir -PathType Container) {
                    $tabMatches = @(Get-ChildItem -Path $parentDir -Filter "$filePattern*" -ErrorAction SilentlyContinue |
                        Where-Object {
                            $_.PSIsContainer -or
                            $_.Extension -in @('.exe', '.msi') -or
                            $Filter -eq "*"
                        } |
                        ForEach-Object {
                            # Return relative path from BasePath
                            $fullPath = $_.FullName
                            if ($fullPath.StartsWith($BasePath)) {
                                $relativePath = $fullPath.Substring($BasePath.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
                                if ($_.PSIsContainer) {
                                    $relativePath + [IO.Path]::DirectorySeparatorChar
                                } else {
                                    $relativePath
                                }
                            } else {
                                if ($_.PSIsContainer) {
                                    $fullPath + [IO.Path]::DirectorySeparatorChar
                                } else {
                                    $fullPath
                                }
                            }
                        })
                } else {
                    $tabMatches = @()
                }
            }

            if ($tabMatches.Count -gt 0) {
                $tabIndex = ($tabIndex + 1) % $tabMatches.Count

                # Clear current input
                Write-Host ("`b" * $currentInput.Length) -NoNewline
                Write-Host (" " * $currentInput.Length) -NoNewline
                Write-Host ("`b" * $currentInput.Length) -NoNewline

                $currentInput = $tabMatches[$tabIndex]
                $lastTabInput = $currentInput
                Write-Host $currentInput -NoNewline -ForegroundColor Cyan
            }
        }
        elseif ($isBackspace) {
            if ($currentInput.Length -gt 0) {
                $currentInput = $currentInput.Substring(0, $currentInput.Length - 1)
                Write-Host "`b `b" -NoNewline
                $tabIndex = -1
            }
        }
        elseif ($isEscape) {
            Write-Host ("`b" * $currentInput.Length) -NoNewline
            Write-Host (" " * $currentInput.Length) -NoNewline
            Write-Host ("`b" * $currentInput.Length) -NoNewline
            $currentInput = ""
            $tabIndex = -1
        }
        else {
            $char = $keyChar
            # Allow path characters including :, /, \, ., -, _, spaces
            if ($char -and ([char]::IsLetterOrDigit($char) -or
                $char -in @(' ', '-', '_', '.', '/', '\', ':', '(', ')'))) {
                $currentInput += $char
                Write-Host $char -NoNewline
                $tabIndex = -1
            }
        }
    }
}

function Get-ExistingVendors {
    <#
    .SYNOPSIS
        Gets list of existing vendor display names for auto-completion.
    .DESCRIPTION
        Scans vendor folders and reads the Publisher field from manifest files
        to return the display name (with spaces/punctuation) instead of folder names.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$BasePath = (Get-Location).Path
    )

    if (Test-Path $BasePath) {
        $vendorFolders = Get-ChildItem -Path $BasePath -Directory -ErrorAction SilentlyContinue
        $vendors = @{}

        foreach ($vendorFolder in $vendorFolders) {
            # Look for any manifest in vendor/app/version/manifest.json
            $manifests = Get-ChildItem -Path $vendorFolder.FullName -Recurse -Filter "manifest.json" -ErrorAction SilentlyContinue | Select-Object -First 1

            if ($manifests) {
                try {
                    $manifest = Get-Content -Path $manifests.FullName -Raw | ConvertFrom-Json
                    if ($manifest.Publisher) {
                        $vendors[$manifest.Publisher] = $true
                    }
                }
                catch {
                    # Fall back to folder name if manifest can't be read
                    $vendors[$vendorFolder.Name] = $true
                }
            }
            else {
                # No manifest found, use folder name
                $vendors[$vendorFolder.Name] = $true
            }
        }

        $vendors.Keys | Sort-Object
    }
}

function Get-ExistingApps {
    <#
    .SYNOPSIS
        Gets list of existing app display names under a vendor for auto-completion.
    .DESCRIPTION
        Scans app folders and reads the AppName field from manifest files
        to return the display name (with spaces/punctuation) instead of folder names.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$Vendor
    )

    $vendorPath = Join-Path $BasePath $Vendor
    if (Test-Path $vendorPath) {
        $appFolders = Get-ChildItem -Path $vendorPath -Directory -ErrorAction SilentlyContinue
        $apps = @{}

        foreach ($appFolder in $appFolders) {
            # Look for any manifest in app/version/manifest.json
            $manifests = Get-ChildItem -Path $appFolder.FullName -Recurse -Filter "manifest.json" -ErrorAction SilentlyContinue | Select-Object -First 1

            if ($manifests) {
                try {
                    $manifest = Get-Content -Path $manifests.FullName -Raw | ConvertFrom-Json
                    if ($manifest.AppName) {
                        $apps[$manifest.AppName] = $true
                    }
                }
                catch {
                    # Fall back to folder name if manifest can't be read
                    $apps[$appFolder.Name] = $true
                }
            }
            else {
                # No manifest found, use folder name
                $apps[$appFolder.Name] = $true
            }
        }

        $apps.Keys | Sort-Object
    }
}

function Get-ExistingVersions {
    <#
    .SYNOPSIS
        Gets list of existing version folders under an app for auto-completion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$Vendor,

        [Parameter(Mandatory)]
        [string]$AppName
    )

    $appPath = Join-Path $BasePath $Vendor $AppName
    if (Test-Path $appPath) {
        Get-ChildItem -Path $appPath -Directory -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Name
    }
}

function Select-Action1Organization {
    <#
    .SYNOPSIS
        Prompts user to select an Action1 organization.

    .DESCRIPTION
        Fetches available organizations from the API and displays an interactive
        selection menu. Supports "All" option for enterprise-wide scope.

    .PARAMETER IncludeAll
        If specified, includes "All (Enterprise-wide)" as the first option.
        Defaults to $true.

    .PARAMETER Prompt
        Custom prompt text. Defaults to "Select Organization".

    .OUTPUTS
        Returns a hashtable with 'Id' and 'Name' properties, or $null if cancelled.

    .EXAMPLE
        $org = Select-Action1Organization
        # Returns @{ Id = "org-123"; Name = "Contoso Corp" }

    .EXAMPLE
        $org = Select-Action1Organization -IncludeAll:$false
        # Only shows specific organizations, no "All" option
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [bool]$IncludeAll = $true,

        [Parameter()]
        [string]$Prompt = "Select Organization"
    )

    try {
        Write-Host "`nFetching available organizations..." -ForegroundColor Gray
        $orgsResponse = Invoke-Action1ApiRequest -Endpoint "organizations" -Method GET

        # Handle both array and items-wrapped responses
        $orgs = if ($orgsResponse.items) { @($orgsResponse.items) } else { @($orgsResponse) }

        if ($orgs.Count -eq 0) {
            if ($IncludeAll) {
                Write-Host "No specific organizations found. Using 'all' scope." -ForegroundColor Yellow
                return @{ Id = "all"; Name = "All (Enterprise-wide)" }
            } else {
                Write-Warning "No organizations found."
                return $null
            }
        }

        Write-Host "`n${Prompt}:" -ForegroundColor Cyan

        if ($IncludeAll) {
            Write-Host "  [0] All (Enterprise-wide)"
        }

        for ($i = 0; $i -lt $orgs.Count; $i++) {
            Write-Host "  [$($i + 1)] $($orgs[$i].name)"
        }

        $maxSelection = $orgs.Count
        $selectionPrompt = if ($IncludeAll) { "0-$maxSelection" } else { "1-$maxSelection" }
        $selection = Read-Host "`nEnter selection ($selectionPrompt)"

        if (-not $selection) {
            if ($IncludeAll) {
                Write-Host "Selected: All (Enterprise-wide)" -ForegroundColor Green
                return @{ Id = "all"; Name = "All (Enterprise-wide)" }
            } else {
                return $null
            }
        }

        $selNum = [int]$selection

        if ($IncludeAll -and $selNum -eq 0) {
            Write-Host "Selected: All (Enterprise-wide)" -ForegroundColor Green
            return @{ Id = "all"; Name = "All (Enterprise-wide)" }
        }

        $orgIndex = $selNum - 1
        if ($orgIndex -ge 0 -and $orgIndex -lt $orgs.Count) {
            $selectedOrg = $orgs[$orgIndex]
            Write-Host "Selected: $($selectedOrg.name)" -ForegroundColor Green
            return @{ Id = $selectedOrg.id; Name = $selectedOrg.name }
        }

        Write-Host "Invalid selection." -ForegroundColor Yellow
        if ($IncludeAll) {
            Write-Host "Using 'all' scope." -ForegroundColor Yellow
            return @{ Id = "all"; Name = "All (Enterprise-wide)" }
        }
        return $null
    }
    catch {
        Write-Action1Log "Failed to fetch organizations: $_" -Level WARN
        $manualId = Read-Host "Enter Action1 Organization ID manually (or 'all' for all organizations)"
        if (-not $manualId) { $manualId = "all" }
        return @{ Id = $manualId; Name = $manualId }
    }
}

#endregion Helper Functions

#region Logging Functions

function Write-Action1Log {
    <#
    .SYNOPSIS
        Internal logging function for the module.

    .DESCRIPTION
        Provides structured logging with levels: TRACE, DEBUG, INFO, WARN, ERROR, SILENT.
        File logging is one level more verbose than console output:
        - SILENT console → INFO to file
        - ERROR console → WARN to file
        - WARN console → INFO to file
        - INFO console → DEBUG to file
        - DEBUG/TRACE console → TRACE to file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',
        
        [Parameter()]
        [object]$Data,
        
        [Parameter()]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )
    
    # Determine file log level (one level more verbose than console)
    $fileLogLevel = switch ($script:LogLevel) {

        'SILENT' { 'INFO' }
        'INFO'   { 'WARN' }
        'WARN'   { 'ERROR' }
        'ERROR'  { 'BEBUG' }
        'DEBUG'  { 'TRACE' }
        'TRACE'  { 'TRACE' }

    }

    # Check if this message should be shown on console or written to file
    $shouldDisplayConsole = $script:LogLevels[$Level] -ge $script:LogLevels[$script:LogLevel]
    $shouldWriteToFile = $script:LogLevels[$Level] -ge $script:LogLevels[$fileLogLevel]
    $isSilent = $script:LogLevel -eq 'SILENT'

    # Skip entirely if below both thresholds
    if (-not $shouldDisplayConsole -and -not $shouldWriteToFile) {
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $callerInfo = (Get-PSCallStack)[1]
    $caller = "$($callerInfo.Command)"

    # Build log message
    $logMessage = "[$timestamp] [$Level] [$caller] $Message"

    # Only write to console if not in SILENT mode
    if (-not $isSilent) {
        # Color coding for console output
        $color = switch ($Level) {
            'TRACE' { 'Gray' }
            'DEBUG' { 'Cyan' }
            'INFO' { 'White' }
            'WARN' { 'Yellow' }
            'ERROR' { 'Red' }
        }

        # Write to console
        Write-Host $logMessage -ForegroundColor $color
    }

    # Add data if provided
    if ($Data) {
        $dataString = $Data | ConvertTo-Json -Depth 5 -Compress
        $dataMessage = "[$timestamp] [$Level] [$caller] DATA: $dataString"
        if (-not $isSilent) {
            Write-Host $dataMessage -ForegroundColor DarkGray
        }
        $logMessage += "`n$dataMessage"
    }

    # Add error details if provided
    if ($ErrorRecord) {
        $errorMessage = "[$timestamp] [$Level] [$caller] ERROR DETAILS: $($ErrorRecord.Exception.Message)"
        $errorMessage += "`n  at $($ErrorRecord.InvocationInfo.ScriptName):$($ErrorRecord.InvocationInfo.ScriptLineNumber)"
        if ($ErrorRecord.Exception.StackTrace) {
            $errorMessage += "`n  StackTrace: $($ErrorRecord.Exception.StackTrace)"
        }
        if (-not $isSilent) {
            Write-Host $errorMessage -ForegroundColor Red
        }
        $logMessage += "`n$errorMessage"
    }

    # Write to log file if configured and message meets file threshold
    if ($script:LogFilePath -and $shouldWriteToFile) {
        try {
            $logMessage | Add-Content -Path $script:LogFilePath -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file: $($_.Exception.Message)"
        }
    }
}

function Set-Action1LogLevel {
    <#
    .SYNOPSIS
        Sets the logging level for the module.

    .DESCRIPTION
        Controls which log messages are displayed based on severity.
        TRACE (most verbose) > DEBUG > INFO > WARN > ERROR > SILENT (no console output)

        File logging is automatically one level more verbose than console:
        - SILENT → logs INFO and above to file
        - ERROR → logs WARN and above to file
        - WARN → logs INFO and above to file
        - INFO → logs DEBUG and above to file
        - DEBUG/TRACE → logs TRACE and above to file

    .PARAMETER Level
        The minimum log level to display on console. Default is SILENT.

    .PARAMETER LogFile
        Optional path to write logs to a file.

    .EXAMPLE
        Set-Action1LogLevel -Level DEBUG

    .EXAMPLE
        Set-Action1LogLevel -Level TRACE -LogFile "C:\Logs\action1-deployment.log"

    .EXAMPLE
        Set-Action1LogLevel -Level SILENT -LogFile "C:\Logs\action1.log"
        # Suppresses console output but logs INFO and above to file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'SILENT')]
        [string]$Level,
        
        [Parameter()]
        [string]$LogFile
    )

    # Set default log file path cross-platform
    if (-not $LogFile) {
        $tempDir = if ($ENV:TEMP) { $ENV:TEMP } elseif ($ENV:TMPDIR) { $ENV:TMPDIR } else { "/tmp" }
        $LogFile = Join-Path $tempDir "action1-deployment.log"
    }
    
    $script:LogLevel = $Level
    Write-Host "Log level set to: $Level" -ForegroundColor Green
    
    if ($LogFile) {
        $script:LogFilePath = $LogFile
        
        # Create log directory if it doesn't exist
        $logDir = Split-Path $LogFile -Parent
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        # Initialize log file
        $header = @"
==============================================
Action1 Deployment Log
Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Log Level: $Level
==============================================

"@
        $header | Set-Content -Path $LogFile
        Write-Host "Logging to file: $LogFile" -ForegroundColor Green
    }
}

function Get-Action1LogLevel {
    <#
    .SYNOPSIS
        Gets the current logging level.
    
    .EXAMPLE
        Get-Action1LogLevel
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "Current log level: $script:LogLevel" -ForegroundColor Cyan
    if ($script:LogFilePath) {
        Write-Host "Log file: $script:LogFilePath" -ForegroundColor Cyan
    }
    
    return @{
        Level = $script:LogLevel
        LogFile = $script:LogFilePath
    }
}

#endregion

#region Progress and UI Functions

function Start-Action1Spinner {
    <#
    .SYNOPSIS
        Starts an animated spinner for long-running operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter(Mandatory)]
        [ref]$SpinnerJob
    )
    
    $spinnerScript = {
        param($msg)
        $spinChars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
        $i = 0
        while ($true) {
            Write-Host "`r$msg $($spinChars[$i % $spinChars.Length]) " -NoNewline -ForegroundColor Cyan
            Start-Sleep -Milliseconds 100
            $i++
        }
    }
    
    $SpinnerJob.Value = Start-Job -ScriptBlock $spinnerScript -ArgumentList $Message
}

function Stop-Action1Spinner {
    <#
    .SYNOPSIS
        Stops the animated spinner.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $SpinnerJob,
        
        [Parameter()]
        [string]$CompletionMessage = "Done"
    )
    
    if ($SpinnerJob) {
        Stop-Job $SpinnerJob -ErrorAction SilentlyContinue
        Remove-Job $SpinnerJob -ErrorAction SilentlyContinue
        Write-Host "`r$CompletionMessage                    " -ForegroundColor Green
    }
}

function Write-Action1Progress {
    <#
    .SYNOPSIS
        Displays progress bar for operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Activity,
        
        [Parameter()]
        [string]$Status = "Processing",
        
        [Parameter(Mandatory)]
        [int]$PercentComplete,
        
        [Parameter()]
        [int]$Id = 0,
        
        [Parameter()]
        [int]$ParentId = -1
    )
    
    $params = @{
        Activity = $Activity
        Status = $Status
        PercentComplete = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
        Id = $Id
    }
    
    if ($ParentId -ge 0) {
        $params['ParentId'] = $ParentId
    }
    
    Write-Progress @params
}

function ConvertTo-FileSize {
    <#
    .SYNOPSIS
        Converts bytes to human-readable file size.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [long]$Bytes
    )
    
    $sizes = @('B', 'KB', 'MB', 'GB', 'TB')
    $order = 0
    $value = $Bytes
    
    while ($value -ge 1024 -and $order -lt $sizes.Length - 1) {
        $value = $value / 1024
        $order++
    }
    
    return "{0:N2} {1}" -f $value, $sizes[$order]
}

function Invoke-Action1FileUpload {
    <#
    .SYNOPSIS
        Uploads a file with progress tracking and chunking support.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [string]$Endpoint,
        
        [Parameter()]
        [int]$ChunkSizeMB = 32,
        
        [Parameter()]
        [hashtable]$AdditionalData
    )
    
    Write-Action1Log "Starting file upload: $FilePath" -Level INFO
    
    if (-not (Test-Path $FilePath)) {
        throw "File not found: $FilePath"
    }
    
    $fileInfo = Get-Item $FilePath
    $fileSize = $fileInfo.Length
    $fileName = $fileInfo.Name
    
    Write-Action1Log "File size: $(ConvertTo-FileSize -Bytes $fileSize)" -Level DEBUG
    
    # For small files (< 32MB), upload directly
    if ($fileSize -lt (32 * 1024 * 1024)) {
        Write-Action1Log "File is small, uploading directly without chunking" -Level DEBUG
        return Invoke-Action1DirectUpload -FilePath $FilePath -Endpoint $Endpoint -AdditionalData $AdditionalData
    }
    
    # For large files, use chunked upload
    Write-Action1Log "File is large, using chunked upload" -Level DEBUG
    return Invoke-Action1ChunkedUpload -FilePath $FilePath -Endpoint $Endpoint -ChunkSizeMB $ChunkSizeMB -AdditionalData $AdditionalData
}

function Invoke-Action1DirectUpload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [string]$Endpoint,
        
        [Parameter()]
        [hashtable]$AdditionalData
    )
    
    $fileInfo = Get-Item $FilePath
    $fileName = $fileInfo.Name
    $fileSize = $fileInfo.Length
    
    Write-Action1Progress -Activity "Uploading $fileName" -Status "Reading file..." -PercentComplete 0 -Id 1
    
    try {
        $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
        Write-Action1Log "File read into memory: $(ConvertTo-FileSize -Bytes $fileBytes.Length)" -Level DEBUG
        
        Write-Action1Progress -Activity "Uploading $fileName" -Status "Encoding..." -PercentComplete 25 -Id 1
        
        $base64Content = [Convert]::ToBase64String($fileBytes)
        Write-Action1Log "File encoded to base64: $($base64Content.Length) characters" -Level DEBUG
        
        Write-Action1Progress -Activity "Uploading $fileName" -Status "Uploading to Action1..." -PercentComplete 50 -Id 1
        
        $uploadData = @{
            fileName = $fileName
            fileData = $base64Content
        }
        
        if ($AdditionalData) {
            foreach ($key in $AdditionalData.Keys) {
                $uploadData[$key] = $AdditionalData[$key]
            }
        }
        
        $response = Invoke-Action1ApiRequest -Endpoint $Endpoint -Method POST -Body $uploadData
        
        Write-Action1Progress -Activity "Uploading $fileName" -Status "Complete" -PercentComplete 100 -Id 1
        Start-Sleep -Milliseconds 500
        Write-Progress -Activity "Uploading $fileName" -Id 1 -Completed
        
        Write-Action1Log "File uploaded successfully" -Level INFO
        return $response
    }
    catch {
        Write-Progress -Activity "Uploading $fileName" -Id 1 -Completed
        Write-Action1Log "Direct upload failed" -Level ERROR -ErrorRecord $_
        throw
    }
}

function Invoke-Action1ChunkedUpload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter()]
        [int]$ChunkSizeMB = 5,

        [Parameter()]
        [hashtable]$AdditionalData,

        [Parameter()]
        [int]$ThrottleLimit = 4,

        [Parameter()]
        [switch]$Sequential
    )

    $fileInfo = Get-Item $FilePath
    $fileName = $fileInfo.Name
    $fileSize = $fileInfo.Length
    $chunkSize = $ChunkSizeMB * 1024 * 1024
    $totalChunks = [Math]::Ceiling($fileSize / $chunkSize)

    # Use sequential for small files (< 5 chunks) or if explicitly requested
    if ($Sequential -or $totalChunks -lt 5) {
        return Invoke-Action1ChunkedUploadSequential -FilePath $FilePath -Endpoint $Endpoint -ChunkSizeMB $ChunkSizeMB -AdditionalData $AdditionalData
    }

    Write-Action1Log "Parallel chunked upload: $totalChunks chunks of $(ConvertTo-FileSize -Bytes $chunkSize) (ThrottleLimit: $ThrottleLimit)" -Level INFO

    $uploadId = [Guid]::NewGuid().ToString()

    try {
        # Pre-read all chunks into memory (required for parallel processing)
        Write-Action1Progress -Activity "Uploading $fileName" -Status "Reading file chunks..." -PercentComplete 0 -Id 1
        Write-Action1Log "Pre-reading file chunks into memory..." -Level DEBUG

        $chunks = @()
        $fileStream = [System.IO.File]::OpenRead($FilePath)

        for ($i = 1; $i -le $totalChunks; $i++) {
            $remainingBytes = $fileStream.Length - $fileStream.Position
            $currentChunkSize = [Math]::Min($chunkSize, $remainingBytes)

            $buffer = New-Object byte[] $currentChunkSize
            $null = $fileStream.Read($buffer, 0, $currentChunkSize)

            $chunks += @{
                ChunkNumber = $i
                Data = [Convert]::ToBase64String($buffer)
                Size = $currentChunkSize
            }

            $readPercent = [int](($i / $totalChunks) * 25)  # Reading is 0-25%
            Write-Action1Progress -Activity "Uploading $fileName" -Status "Reading chunk $i of $totalChunks..." -PercentComplete $readPercent -Id 1
        }

        $fileStream.Close()
        $fileStream.Dispose()
        $fileStream = $null

        Write-Action1Log "All $totalChunks chunks read into memory" -Level DEBUG

        # Prepare data needed for parallel execution
        $baseUri = $script:Action1BaseUri
        $token = Get-Action1AccessToken
        $chunkEndpoint = "$Endpoint/chunk"

        # Thread-safe dictionary to track chunk status: 0=pending, 1=uploading, 2=complete, -1=failed
        $chunkStatus = [System.Collections.Concurrent.ConcurrentDictionary[int, int]]::new()
        for ($i = 1; $i -le $totalChunks; $i++) {
            $null = $chunkStatus.TryAdd($i, 0)
        }

        # Track which slots (progress bar IDs) are assigned to which chunks
        $slotAssignments = [System.Collections.Concurrent.ConcurrentDictionary[int, int]]::new()

        Write-Action1Progress -Activity "Uploading $fileName" -Status "Uploading $totalChunks chunks in parallel..." -PercentComplete 25 -Id 1

        # Start a background runspace to update progress bars
        $progressRunspace = [runspacefactory]::CreateRunspace()
        $progressRunspace.Open()
        $progressRunspace.SessionStateProxy.SetVariable('chunkStatus', $chunkStatus)
        $progressRunspace.SessionStateProxy.SetVariable('slotAssignments', $slotAssignments)
        $progressRunspace.SessionStateProxy.SetVariable('totalChunks', $totalChunks)
        $progressRunspace.SessionStateProxy.SetVariable('fileName', $fileName)
        $progressRunspace.SessionStateProxy.SetVariable('throttleLimit', $ThrottleLimit)
        $progressRunspace.SessionStateProxy.SetVariable('chunkSize', $chunkSize)

        $progressScript = {
            while ($true) {
                $completedCount = ($chunkStatus.Values | Where-Object { $_ -eq 2 }).Count
                $failedCount = ($chunkStatus.Values | Where-Object { $_ -eq -1 }).Count
                $uploadingChunks = $chunkStatus.GetEnumerator() | Where-Object { $_.Value -eq 1 } | Select-Object -ExpandProperty Key

                # Update main progress bar (ID 1)
                $overallPercent = 25 + [int](($completedCount / $totalChunks) * 70)  # 25-95%
                $status = "Completed: $completedCount/$totalChunks"
                if ($failedCount -gt 0) { $status += " (Failed: $failedCount)" }
                Write-Progress -Activity "Uploading $fileName" -Status $status -PercentComplete $overallPercent -Id 1

                # Update individual chunk progress bars (IDs 10-1x based on throttle limit)
                $slot = 0
                foreach ($chunkNum in ($uploadingChunks | Sort-Object | Select-Object -First $throttleLimit)) {
                    $slot++
                    $progressId = 10 + $slot
                    $chunkSizeMB = [math]::Round($chunkSize / 1MB, 1)
                    Write-Progress -Activity "Chunk $chunkNum" -Status "Uploading ($chunkSizeMB MB)..." -PercentComplete 50 -Id $progressId -ParentId 1
                    $null = $slotAssignments.AddOrUpdate($chunkNum, $progressId, { param($k, $v) $progressId })
                }

                # Clear progress bars for completed chunks
                foreach ($entry in $slotAssignments.GetEnumerator()) {
                    $chunkNum = $entry.Key
                    $progressId = $entry.Value
                    $status = 0
                    if ($chunkStatus.TryGetValue($chunkNum, [ref]$status) -and ($status -eq 2 -or $status -eq -1)) {
                        Write-Progress -Activity "Chunk $chunkNum" -Id $progressId -Completed
                        $null = $slotAssignments.TryRemove($chunkNum, [ref]$null)
                    }
                }

                # Exit when all chunks are done
                if (($completedCount + $failedCount) -ge $totalChunks) {
                    # Clear any remaining progress bars
                    for ($i = 11; $i -le (10 + $throttleLimit); $i++) {
                        Write-Progress -Activity "Chunk" -Id $i -Completed
                    }
                    break
                }

                Start-Sleep -Milliseconds 200
            }
        }

        $progressPipeline = $progressRunspace.CreatePipeline()
        $progressPipeline.Commands.AddScript($progressScript)
        $progressHandle = $progressPipeline.BeginInvoke()

        # Upload chunks in parallel
        $uploadResults = $chunks | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            $chunk = $_
            $uploadIdLocal = $using:uploadId
            $fileNameLocal = $using:fileName
            $totalChunksLocal = $using:totalChunks
            $baseUriLocal = $using:baseUri
            $tokenLocal = $using:token
            $endpointLocal = $using:chunkEndpoint
            $additionalDataLocal = $using:AdditionalData
            $statusDict = $using:chunkStatus

            # Mark as uploading
            $null = $statusDict.TryUpdate($chunk.ChunkNumber, 1, 0)

            $chunkData = @{
                uploadId = $uploadIdLocal
                fileName = $fileNameLocal
                chunkNumber = $chunk.ChunkNumber
                totalChunks = $totalChunksLocal
                chunkData = $chunk.Data
            }

            # Add additional data to first chunk only
            if ($chunk.ChunkNumber -eq 1 -and $additionalDataLocal) {
                foreach ($key in $additionalDataLocal.Keys) {
                    $chunkData[$key] = $additionalDataLocal[$key]
                }
            }

            $uri = "$baseUriLocal/$endpointLocal"
            $headers = @{
                'Authorization' = "Bearer $tokenLocal"
                'Content-Type'  = 'application/json'
                'Accept'        = 'application/json'
            }

            try {
                $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body ($chunkData | ConvertTo-Json -Depth 10) -ErrorAction Stop

                # Mark as complete
                $null = $statusDict.TryUpdate($chunk.ChunkNumber, 2, 1)

                return @{
                    ChunkNumber = $chunk.ChunkNumber
                    Success = $true
                    Response = $response
                }
            }
            catch {
                # Mark as failed
                $null = $statusDict.TryUpdate($chunk.ChunkNumber, -1, 1)

                return @{
                    ChunkNumber = $chunk.ChunkNumber
                    Success = $false
                    Error = $_.Exception.Message
                }
            }
        }

        # Wait for progress runspace to finish
        $null = $progressPipeline.EndInvoke($progressHandle)
        $progressPipeline.Dispose()
        $progressRunspace.Close()
        $progressRunspace.Dispose()

        # Check for failures
        $failures = $uploadResults | Where-Object { -not $_.Success }
        if ($failures) {
            $failedChunks = ($failures | ForEach-Object { $_.ChunkNumber }) -join ', '
            throw "Failed to upload chunks: $failedChunks. Errors: $(($failures | ForEach-Object { $_.Error }) -join '; ')"
        }

        Write-Action1Log "All $totalChunks chunks uploaded successfully" -Level INFO

        # Finalize upload
        Write-Action1Progress -Activity "Uploading $fileName" -Status "Finalizing upload..." -PercentComplete 95 -Id 1
        Write-Action1Log "Finalizing chunked upload" -Level INFO

        $finalizeData = @{
            uploadId = $uploadId
            fileName = $fileName
            totalChunks = $totalChunks
        }

        $response = Invoke-Action1ApiRequest -Endpoint "$Endpoint/finalize" -Method POST -Body $finalizeData

        Write-Action1Progress -Activity "Uploading $fileName" -Status "Complete" -PercentComplete 100 -Id 1
        Start-Sleep -Milliseconds 500
        Write-Progress -Activity "Uploading $fileName" -Id 1 -Completed

        Write-Action1Log "Parallel chunked upload completed successfully" -Level INFO
        return $response
    }
    catch {
        if ($fileStream) {
            $fileStream.Close()
            $fileStream.Dispose()
        }

        # Clean up progress bars
        Write-Progress -Activity "Uploading $fileName" -Id 1 -Completed
        for ($i = 11; $i -le (10 + $ThrottleLimit); $i++) {
            Write-Progress -Activity "Chunk" -Id $i -Completed
        }

        Write-Action1Log "Parallel chunked upload failed" -Level ERROR -ErrorRecord $_
        throw
    }
}

function Invoke-Action1ChunkedUploadSequential {
    <#
    .SYNOPSIS
        Sequential chunked upload (fallback for small files or when parallel is disabled).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter()]
        [int]$ChunkSizeMB = 5,

        [Parameter()]
        [hashtable]$AdditionalData
    )

    $fileInfo = Get-Item $FilePath
    $fileName = $fileInfo.Name
    $fileSize = $fileInfo.Length
    $chunkSize = $ChunkSizeMB * 1024 * 1024
    $totalChunks = [Math]::Ceiling($fileSize / $chunkSize)

    Write-Action1Log "Sequential chunked upload: $totalChunks chunks of $(ConvertTo-FileSize -Bytes $chunkSize)" -Level INFO

    try {
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        $uploadId = [Guid]::NewGuid().ToString()
        $currentChunk = 0

        Write-Action1Progress -Activity "Uploading $fileName" -Status "Initializing..." -PercentComplete 0 -Id 1

        while ($fileStream.Position -lt $fileStream.Length) {
            $currentChunk++
            $remainingBytes = $fileStream.Length - $fileStream.Position
            $currentChunkSize = [Math]::Min($chunkSize, $remainingBytes)

            $buffer = New-Object byte[] $currentChunkSize
            $bytesRead = $fileStream.Read($buffer, 0, $currentChunkSize)

            $overallPercent = [int](($fileStream.Position / $fileStream.Length) * 100)
            $uploadedSize = ConvertTo-FileSize -Bytes $fileStream.Position
            $totalSize = ConvertTo-FileSize -Bytes $fileSize

            Write-Action1Progress `
                -Activity "Uploading $fileName ($uploadedSize / $totalSize)" `
                -Status "Chunk $currentChunk of $totalChunks" `
                -PercentComplete $overallPercent `
                -Id 1

            # Show chunk progress as child progress bar
            Write-Action1Progress `
                -Activity "Current Chunk" `
                -Status "Encoding and uploading..." `
                -PercentComplete 0 `
                -Id 2 `
                -ParentId 1

            $base64Chunk = [Convert]::ToBase64String($buffer)

            Write-Action1Progress `
                -Activity "Current Chunk" `
                -Status "Uploading to server..." `
                -PercentComplete 50 `
                -Id 2 `
                -ParentId 1

            Write-Action1Log "Uploading chunk $currentChunk/$totalChunks ($(ConvertTo-FileSize -Bytes $bytesRead))" -Level DEBUG

            $chunkData = @{
                uploadId = $uploadId
                fileName = $fileName
                chunkNumber = $currentChunk
                totalChunks = $totalChunks
                chunkData = $base64Chunk
            }

            if ($currentChunk -eq 1 -and $AdditionalData) {
                foreach ($key in $AdditionalData.Keys) {
                    $chunkData[$key] = $AdditionalData[$key]
                }
            }

            $chunkResponse = Invoke-Action1ApiRequest -Endpoint "$Endpoint/chunk" -Method POST -Body $chunkData

            Write-Action1Progress `
                -Activity "Current Chunk" `
                -Status "Complete" `
                -PercentComplete 100 `
                -Id 2 `
                -ParentId 1

            Write-Action1Log "Chunk $currentChunk uploaded successfully" -Level TRACE -Data $chunkResponse

            Start-Sleep -Milliseconds 100
        }

        $fileStream.Close()
        $fileStream.Dispose()

        # Finalize upload
        Write-Action1Progress `
            -Activity "Uploading $fileName" `
            -Status "Finalizing upload..." `
            -PercentComplete 95 `
            -Id 1

        Write-Action1Log "Finalizing chunked upload" -Level INFO

        $finalizeData = @{
            uploadId = $uploadId
            fileName = $fileName
            totalChunks = $totalChunks
        }

        $response = Invoke-Action1ApiRequest -Endpoint "$Endpoint/finalize" -Method POST -Body $finalizeData

        Write-Action1Progress `
            -Activity "Uploading $fileName" `
            -Status "Complete" `
            -PercentComplete 100 `
            -Id 1

        Start-Sleep -Milliseconds 500
        Write-Progress -Activity "Uploading $fileName" -Id 1 -Completed
        Write-Progress -Activity "Current Chunk" -Id 2 -Completed

        Write-Action1Log "Sequential chunked upload completed successfully" -Level INFO
        return $response
    }
    catch {
        if ($fileStream) {
            $fileStream.Close()
            $fileStream.Dispose()
        }

        Write-Progress -Activity "Uploading $fileName" -Id 1 -Completed
        Write-Progress -Activity "Current Chunk" -Id 2 -Completed

        Write-Action1Log "Sequential chunked upload failed" -Level ERROR -ErrorRecord $_
        throw
    }
}

#region Software Repository API Functions

function Get-Action1SoftwareRepositories {
    <#
    .SYNOPSIS
        Lists custom software repositories from Action1.

    .DESCRIPTION
        Retrieves a list of custom software repositories for the specified organization.

    .PARAMETER OrganizationId
        The organization ID (or "all" for enterprise-wide).

    .OUTPUTS
        Returns an array of repository objects with id, name, vendor, platform properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationId
    )

    Write-Action1Log "Fetching custom software repositories..." -Level INFO

    $token = Get-Action1AccessToken
    $uri = "$script:Action1BaseUri/software-repository/$OrganizationId`?custom=yes&builtin=no&limit=100"

    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }

    # TRACE: Log full request details
    Write-Action1Log "========== REQUEST ==========" -Level TRACE
    Write-Action1Log "GET $uri" -Level TRACE
    Write-Action1Log "Request Headers:" -Level TRACE
    Write-Action1Log "  Authorization: Bearer ***MASKED***" -Level TRACE
    Write-Action1Log "  Content-Type: $($headers['Content-Type'])" -Level TRACE
    Write-Action1Log "  Accept: $($headers['Accept'])" -Level TRACE
    Write-Action1Log "=============================" -Level TRACE

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $webResponse = Invoke-WebRequest -Uri $uri -Method GET -Headers $headers -ErrorAction Stop
        $stopwatch.Stop()

        # TRACE: Log full response details
        Write-Action1Log "========== RESPONSE ==========" -Level TRACE
        Write-Action1Log "HTTP Status: $($webResponse.StatusCode) $($webResponse.StatusDescription)" -Level TRACE
        Write-Action1Log "Duration: $($stopwatch.ElapsedMilliseconds)ms" -Level TRACE
        Write-Action1Log "Response Headers:" -Level TRACE
        foreach ($headerName in $webResponse.Headers.Keys) {
            $headerValue = $webResponse.Headers[$headerName]
            if ($headerValue -is [array]) { $headerValue = $headerValue -join ', ' }
            Write-Action1Log "  $headerName`: $headerValue" -Level TRACE
        }
        Write-Action1Log "Content-Length: $($webResponse.Content.Length) bytes" -Level TRACE
        Write-Action1Log "Response Body:" -Level TRACE
        Write-Action1Log $webResponse.Content -Level TRACE
        Write-Action1Log "==============================" -Level TRACE

        $response = $webResponse.Content | ConvertFrom-Json
        $items = if ($response.items) { $response.items } else { @() }
        Write-Action1Log "Found $($items.Count) custom repositories" -Level INFO
        return $items
    }
    catch {
        Write-Action1Log "Failed to list repositories" -Level ERROR -ErrorRecord $_
        throw
    }
}

function New-Action1SoftwareRepository {
    <#
    .SYNOPSIS
        Creates a new software repository in Action1.

    .DESCRIPTION
        Creates a custom software repository with the specified properties.

    .PARAMETER OrganizationId
        The organization ID (or "all" for enterprise-wide).

    .PARAMETER Name
        The repository name.

    .PARAMETER Vendor
        The vendor/publisher name.

    .PARAMETER Description
        Description of the software.

    .PARAMETER InternalNotes
        Internal notes (optional).

    .PARAMETER Platform
        The platform: Windows, Mac, or Linux.

    .OUTPUTS
        Returns the created repository object with its ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationId,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Vendor,

        [Parameter()]
        [string]$Description = "",

        [Parameter()]
        [string]$InternalNotes = "",

        [Parameter(Mandatory)]
        [ValidateSet('Windows', 'Mac', 'Linux')]
        [string]$Platform
    )

    Write-Action1Log "Creating software repository: $Name" -Level INFO

    $token = Get-Action1AccessToken
    $uri = "$script:Action1BaseUri/software-repository/$OrganizationId"

    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }

    $body = @{
        name           = $Name
        vendor         = $Vendor
        description    = $Description
        internal_notes = $InternalNotes
        platform       = $Platform
    } | ConvertTo-Json -Depth 5

    # TRACE: Log full request details
    Write-Action1Log "========== REQUEST ==========" -Level TRACE
    Write-Action1Log "POST $uri" -Level TRACE
    Write-Action1Log "Request Headers:" -Level TRACE
    Write-Action1Log "  Authorization: Bearer ***MASKED***" -Level TRACE
    Write-Action1Log "  Content-Type: $($headers['Content-Type'])" -Level TRACE
    Write-Action1Log "  Accept: $($headers['Accept'])" -Level TRACE
    Write-Action1Log "Request Body:" -Level TRACE
    Write-Action1Log $body -Level TRACE
    Write-Action1Log "=============================" -Level TRACE

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $webResponse = Invoke-WebRequest -Uri $uri -Method POST -Headers $headers -Body $body -ErrorAction Stop
        $stopwatch.Stop()

        # TRACE: Log full response details
        Write-Action1Log "========== RESPONSE ==========" -Level TRACE
        Write-Action1Log "HTTP Status: $($webResponse.StatusCode) $($webResponse.StatusDescription)" -Level TRACE
        Write-Action1Log "Duration: $($stopwatch.ElapsedMilliseconds)ms" -Level TRACE
        Write-Action1Log "Response Headers:" -Level TRACE
        foreach ($headerName in $webResponse.Headers.Keys) {
            $headerValue = $webResponse.Headers[$headerName]
            if ($headerValue -is [array]) { $headerValue = $headerValue -join ', ' }
            Write-Action1Log "  $headerName`: $headerValue" -Level TRACE
        }
        Write-Action1Log "Content-Length: $($webResponse.Content.Length) bytes" -Level TRACE
        Write-Action1Log "Response Body:" -Level TRACE
        Write-Action1Log $webResponse.Content -Level TRACE
        Write-Action1Log "==============================" -Level TRACE

        $response = $webResponse.Content | ConvertFrom-Json

        if (-not $response.id) {
            throw "Repository creation returned no ID"
        }

        Write-Action1Log "Created repository: $Name (ID: $($response.id))" -Level INFO
        return $response
    }
    catch {
        Write-Action1Log "Failed to create repository" -Level ERROR -ErrorRecord $_
        throw
    }
}

function Select-Action1SoftwareRepository {
    <#
    .SYNOPSIS
        Interactively selects or creates a software repository.

    .DESCRIPTION
        Lists existing custom repositories and prompts the user to select one
        or create a new one. If DefaultName is provided and matches an existing
        repository, it will be auto-selected.

    .PARAMETER OrganizationId
        The organization ID (or "all" for enterprise-wide).

    .PARAMETER DefaultName
        Default name for creating a new repository. Also used for auto-matching.

    .PARAMETER DefaultVendor
        Default vendor for creating a new repository.

    .PARAMETER DefaultPlatform
        Default platform for creating a new repository.

    .PARAMETER AutoSelect
        If true and DefaultName matches an existing repo, auto-select it without prompting.

    .OUTPUTS
        Returns a hashtable with Id and IsNew properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationId,

        [Parameter()]
        [string]$DefaultName,

        [Parameter()]
        [string]$DefaultVendor,

        [Parameter()]
        [ValidateSet('Windows', 'Mac', 'Linux')]
        [string]$DefaultPlatform = 'Windows',

        [Parameter()]
        [switch]$AutoSelect
    )

    $repos = Get-Action1SoftwareRepositories -OrganizationId $OrganizationId

    if ($repos.Count -eq 0) {
        Write-Host "`nNo custom repositories found. Creating new one..." -ForegroundColor Yellow

        $name = if ($DefaultName) { $DefaultName } else { Read-Host "Repository name" }
        $vendor = if ($DefaultVendor) { $DefaultVendor } else { Read-Host "Vendor name" }

        $newRepo = New-Action1SoftwareRepository `
            -OrganizationId $OrganizationId `
            -Name $name `
            -Vendor $vendor `
            -Platform $DefaultPlatform

        return @{
            Id    = $newRepo.id
            IsNew = $true
        }
    }

    # Try to auto-match by name if DefaultName is provided
    if ($DefaultName) {
        $matchedRepo = $repos | Where-Object { $_.name -eq $DefaultName } | Select-Object -First 1
        if ($matchedRepo) {
            Write-Host "`nAuto-matched repository: $($matchedRepo.name) ($($matchedRepo.vendor))" -ForegroundColor Green
            return @{
                Id    = $matchedRepo.id
                IsNew = $false
            }
        }
    }

    Write-Host "`nExisting Custom Repositories:" -ForegroundColor Cyan
    Write-Host "  [0] Create new repository" -ForegroundColor Yellow
    for ($i = 0; $i -lt $repos.Count; $i++) {
        $repo = $repos[$i]
        Write-Host "  [$($i + 1)] $($repo.name) ($($repo.vendor)) - $($repo.platform)"
    }

    $maxIndex = $repos.Count
    do {
        $selection = Read-Host "`nEnter selection (0-$maxIndex)"
        $selNum = -1
        if (-not [int]::TryParse($selection, [ref]$selNum) -or ($selNum -lt 0 -or $selNum -gt $maxIndex)) {
            Write-Host "Invalid selection. Please enter a number between 0 and $maxIndex." -ForegroundColor Red
            continue
        }
        break
    } while ($true)

    if ($selNum -eq 0) {
        # Create new repository
        $name = if ($DefaultName) { $DefaultName } else { Read-Host "Repository name" }
        $vendor = if ($DefaultVendor) { $DefaultVendor } else { Read-Host "Vendor name" }

        $newRepo = New-Action1SoftwareRepository `
            -OrganizationId $OrganizationId `
            -Name $name `
            -Vendor $vendor `
            -Platform $DefaultPlatform

        return @{
            Id    = $newRepo.id
            IsNew = $true
        }
    }
    else {
        $selectedRepo = $repos[$selNum - 1]
        Write-Host "Selected: $($selectedRepo.name)" -ForegroundColor Green
        return @{
            Id    = $selectedRepo.id
            IsNew = $false
        }
    }
}

function Get-Action1RepositoryVersions {
    <#
    .SYNOPSIS
        Lists versions for a software repository.

    .DESCRIPTION
        Retrieves all versions for the specified software repository.

    .PARAMETER OrganizationId
        The organization ID (or "all" for enterprise-wide).

    .PARAMETER RepositoryId
        The software repository ID.

    .OUTPUTS
        Returns an array of version objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationId,

        [Parameter(Mandatory)]
        [string]$RepositoryId
    )

    Write-Action1Log "Fetching versions for repository $RepositoryId..." -Level INFO

    $token = Get-Action1AccessToken
    $uri = "$script:Action1BaseUri/software-repository/$OrganizationId/$RepositoryId/versions?limit=100"

    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }

    # TRACE: Log full request details
    Write-Action1Log "========== REQUEST ==========" -Level TRACE
    Write-Action1Log "GET $uri" -Level TRACE
    Write-Action1Log "Request Headers:" -Level TRACE
    Write-Action1Log "  Authorization: Bearer ***MASKED***" -Level TRACE
    Write-Action1Log "  Content-Type: $($headers['Content-Type'])" -Level TRACE
    Write-Action1Log "  Accept: $($headers['Accept'])" -Level TRACE
    Write-Action1Log "=============================" -Level TRACE

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $webResponse = Invoke-WebRequest -Uri $uri -Method GET -Headers $headers -ErrorAction Stop
        $stopwatch.Stop()

        # TRACE: Log full response details
        Write-Action1Log "========== RESPONSE ==========" -Level TRACE
        Write-Action1Log "HTTP Status: $($webResponse.StatusCode) $($webResponse.StatusDescription)" -Level TRACE
        Write-Action1Log "Duration: $($stopwatch.ElapsedMilliseconds)ms" -Level TRACE
        Write-Action1Log "Response Headers:" -Level TRACE
        foreach ($headerName in $webResponse.Headers.Keys) {
            $headerValue = $webResponse.Headers[$headerName]
            if ($headerValue -is [array]) { $headerValue = $headerValue -join ', ' }
            Write-Action1Log "  $headerName`: $headerValue" -Level TRACE
        }
        Write-Action1Log "Content-Length: $($webResponse.Content.Length) bytes" -Level TRACE
        Write-Action1Log "Response Body:" -Level TRACE
        Write-Action1Log $webResponse.Content -Level TRACE
        Write-Action1Log "==============================" -Level TRACE

        $response = $webResponse.Content | ConvertFrom-Json

        # Handle different response formats
        if ($response.type -eq 'Version') {
            # Single version object
            return @($response)
        }
        elseif ($response.items) {
            return $response.items
        }
        else {
            return @()
        }
    }
    catch {
        Write-Action1Log "Failed to list versions" -Level WARN -ErrorRecord $_
        return @()
    }
}

function New-Action1RepositoryVersion {
    <#
    .SYNOPSIS
        Creates a new version in a software repository.

    .DESCRIPTION
        Creates a new version with the specified properties, suitable for uploading
        an installer file.

    .PARAMETER OrganizationId
        The organization ID (or "all" for enterprise-wide).

    .PARAMETER RepositoryId
        The software repository ID.

    .PARAMETER Version
        The version number string.

    .PARAMETER AppNameMatch
        Application name matching pattern for detection.

    .PARAMETER FileName
        The installer file name.

    .PARAMETER Platform
        The upload platform: Windows_64, Windows_32, Windows_ARM64, Mac_AppleSilicon, Mac_IntelCPU.

    .PARAMETER InstallType
        Installation type: msi, exe, msix, or script.

    .PARAMETER ReleaseDate
        Release date (defaults to today).

    .PARAMETER OS
        Array of supported OS versions.

    .PARAMETER SuccessExitCodes
        Comma-separated success exit codes (default "0").

    .PARAMETER RebootExitCodes
        Comma-separated reboot exit codes (default "1641,3010").

    .OUTPUTS
        Returns the created version object with its ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationId,

        [Parameter(Mandatory)]
        [string]$RepositoryId,

        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string]$AppNameMatch,

        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter(Mandatory)]
        [ValidateSet('Windows_64', 'Windows_32', 'Windows_ARM64', 'Mac_AppleSilicon', 'Mac_IntelCPU')]
        [string]$Platform,

        [Parameter()]
        [ValidateSet('msi', 'exe', 'msix', 'script')]
        [string]$InstallType = 'msi',

        [Parameter()]
        [string]$ReleaseDate = (Get-Date -Format 'yyyy-MM-dd'),

        [Parameter()]
        [string[]]$OS = @('Windows 11', 'Windows 10', 'Windows'),

        [Parameter()]
        [string]$SuccessExitCodes = "0",

        [Parameter()]
        [string]$RebootExitCodes = "1641,3010",

        [Parameter()]
        [string]$Notes = "",

        [Parameter()]
        [ValidateSet('Regular Updates', 'Security Updates', 'Critical Updates')]
        [string]$UpdateType = 'Regular Updates',

        [Parameter()]
        [ValidateSet('Unspecified', 'Low', 'Medium', 'High', 'Critical')]
        [string]$SecuritySeverity = 'Unspecified',

        [Parameter()]
        [ValidateSet('Published', 'Draft')]
        [string]$Status = 'Published',

        [Parameter()]
        [ValidateSet('New', 'Approved', 'Declined')]
        [string]$ApprovalStatus = 'Approved',

        [Parameter()]
        [ValidateSet('yes', 'no')]
        [string]$EulaAccepted = 'no',

        [Parameter()]
        [hashtable]$AllPlatformFiles = @{}
    )

    Write-Action1Log "Creating version $Version for repository $RepositoryId..." -Level INFO

    $token = Get-Action1AccessToken
    $uri = "$script:Action1BaseUri/software-repository/$OrganizationId/$RepositoryId/versions"

    # Build the file_name object with all platform-specific entries
    $fileNameObj = @{}

    # Add files from AllPlatformFiles hashtable if provided
    if ($AllPlatformFiles.Count -gt 0) {
        foreach ($plat in $AllPlatformFiles.Keys) {
            $fileNameObj[$plat] = @{
                name = $AllPlatformFiles[$plat]
                type = "cloud"
            }
        }
    }
    else {
        # Fallback to single platform/filename
        $fileNameObj[$Platform] = @{
            name = $FileName
            type = "cloud"
        }
    }

    $body = @{
        version             = $Version
        app_name_match      = $AppNameMatch
        release_date        = $ReleaseDate
        os                  = $OS
        install_type        = $InstallType
        success_exit_codes  = $SuccessExitCodes
        reboot_exit_codes   = $RebootExitCodes
        notes               = $Notes
        update_type         = $UpdateType
        security_severity   = $SecuritySeverity
        status              = $Status
        approval_status     = $ApprovalStatus
        EULA_accepted       = $EulaAccepted
        file_name           = $fileNameObj
    } | ConvertTo-Json -Depth 5

    Write-Action1Log "Version payload: $body" -Level DEBUG

    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }

    # TRACE: Log full request details
    Write-Action1Log "========== REQUEST ==========" -Level TRACE
    Write-Action1Log "POST $uri" -Level TRACE
    Write-Action1Log "Request Headers:" -Level TRACE
    Write-Action1Log "  Authorization: Bearer ***MASKED***" -Level TRACE
    Write-Action1Log "  Content-Type: $($headers['Content-Type'])" -Level TRACE
    Write-Action1Log "  Accept: $($headers['Accept'])" -Level TRACE
    Write-Action1Log "Request Body:" -Level TRACE
    Write-Action1Log $body -Level TRACE
    Write-Action1Log "=============================" -Level TRACE

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $webResponse = Invoke-WebRequest -Uri $uri -Method POST -Headers $headers -Body $body -ErrorAction Stop
        $stopwatch.Stop()

        # TRACE: Log full response details
        Write-Action1Log "========== RESPONSE ==========" -Level TRACE
        Write-Action1Log "HTTP Status: $($webResponse.StatusCode) $($webResponse.StatusDescription)" -Level TRACE
        Write-Action1Log "Duration: $($stopwatch.ElapsedMilliseconds)ms" -Level TRACE
        Write-Action1Log "Response Headers:" -Level TRACE
        foreach ($headerName in $webResponse.Headers.Keys) {
            $headerValue = $webResponse.Headers[$headerName]
            if ($headerValue -is [array]) { $headerValue = $headerValue -join ', ' }
            Write-Action1Log "  $headerName`: $headerValue" -Level TRACE
        }
        Write-Action1Log "Content-Length: $($webResponse.Content.Length) bytes" -Level TRACE
        Write-Action1Log "Response Body:" -Level TRACE
        Write-Action1Log $webResponse.Content -Level TRACE
        Write-Action1Log "==============================" -Level TRACE

        $response = $webResponse.Content | ConvertFrom-Json

        if (-not $response.id) {
            throw "Version creation returned no ID"
        }

        Write-Action1Log "Created version: $Version (ID: $($response.id))" -Level INFO
        return $response
    }
    catch {
        # Try to extract error details from the response
        $errorMessage = $_.Exception.Message
        if ($_.ErrorDetails.Message) {
            try {
                $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
                $errorMessage = "$errorMessage - API Error: $($errorBody | ConvertTo-Json -Compress)"
            }
            catch {
                $errorMessage = "$errorMessage - Response: $($_.ErrorDetails.Message)"
            }
        }
        Write-Action1Log "Failed to create version: $errorMessage" -Level ERROR
        Write-Action1Log "Request URI: $uri" -Level DEBUG
        Write-Action1Log "Request Body: $body" -Level DEBUG
        throw $errorMessage
    }
}

#endregion

function Get-UploadLocationUrl {
    <#
    .SYNOPSIS
        Normalizes the upload location URL returned by the Action1 API.

    .DESCRIPTION
        The X-Upload-Location header may return a relative path (e.g., /API/...)
        or a full URL. This function normalizes it to a full URL.

    .PARAMETER BaseUri
        The base API URI (e.g., https://app.eu.action1.com/api/3.0)

    .PARAMETER Location
        The location value from the X-Upload-Location header.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaseUri,

        [Parameter(Mandatory)]
        [string]$Location
    )

    # If already a full URL, return as-is
    if ($Location -match '^https?://') {
        return $Location
    }

    # Extract origin from base URI
    $uri = [System.Uri]$BaseUri
    $origin = "$($uri.Scheme)://$($uri.Host)"
    if ($uri.Port -ne 80 -and $uri.Port -ne 443) {
        $origin = "$($origin):$($uri.Port)"
    }

    # Handle /API/* paths (convert to /api/3.0/*)
    if ($Location -match '^/API/') {
        $Location = $Location -replace '^/API/', '/api/3.0/'
    }

    # Build full URL
    if ($Location -match '^/') {
        return "$origin$Location"
    }
    else {
        return "$origin/$Location"
    }
}

function Initialize-Action1SoftwareRepoUpload {
    <#
    .SYNOPSIS
        Initializes a resumable upload session for Action1 software repository.

    .DESCRIPTION
        Sends a POST request to the upload endpoint with content metadata headers.
        Returns the upload URL from the X-Upload-Location header.

    .PARAMETER OrganizationId
        The organization ID (or "all" for enterprise-wide).

    .PARAMETER PackageId
        The software repository package ID.

    .PARAMETER VersionId
        The version ID to upload to.

    .PARAMETER Platform
        The platform identifier (e.g., Windows_64, Windows_32, Mac_AppleSilicon).

    .PARAMETER FileSize
        The total file size in bytes.

    .OUTPUTS
        Returns the upload URL to use for chunked uploads.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationId,

        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
        [string]$VersionId,

        [Parameter(Mandatory)]
        [string]$Platform,

        [Parameter(Mandatory)]
        [long]$FileSize
    )

    $token = Get-Action1AccessToken
    $uploadInitUrl = "$script:Action1BaseUri/software-repository/$OrganizationId/$PackageId/versions/$VersionId/upload?platform=$Platform"

    Write-Action1Log "Initializing upload session: $uploadInitUrl" -Level INFO
    Write-Action1Log "File size: $FileSize bytes, Platform: $Platform" -Level DEBUG

    $headers = @{
        'Authorization'           = "Bearer $token"
        'Content-Type'            = 'application/json'
        'Accept'                  = 'application/json'
        'X-Upload-Content-Type'   = 'application/octet-stream'
        'X-Upload-Content-Length' = $FileSize.ToString()
    }

    # TRACE: Log full request details
    Write-Action1Log "========== UPLOAD INIT REQUEST ==========" -Level TRACE
    Write-Action1Log "POST $uploadInitUrl" -Level TRACE
    Write-Action1Log "Request Headers:" -Level TRACE
    foreach ($headerName in $headers.Keys) {
        $headerValue = if ($headerName -eq 'Authorization') { "Bearer ***MASKED***" } else { $headers[$headerName] }
        Write-Action1Log "  $headerName`: $headerValue" -Level TRACE
    }
    Write-Action1Log "Request Body: (empty)" -Level TRACE
    Write-Action1Log "==========================================" -Level TRACE

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Use -SkipHttpErrorCheck to handle 308 responses (PowerShell 7+)
        $response = Invoke-WebRequest -Uri $uploadInitUrl -Method POST -Headers $headers -SkipHttpErrorCheck

        $stopwatch.Stop()
        $statusCode = $response.StatusCode
        $statusDescription = $response.StatusDescription

        # TRACE: Log full response details
        Write-Action1Log "========== UPLOAD INIT RESPONSE ==========" -Level TRACE
        Write-Action1Log "HTTP Status: $statusCode $statusDescription" -Level TRACE
        Write-Action1Log "Duration: $($stopwatch.ElapsedMilliseconds)ms" -Level TRACE
        Write-Action1Log "Response Headers:" -Level TRACE
        foreach ($headerName in $response.Headers.Keys) {
            $headerValue = $response.Headers[$headerName]
            if ($headerValue -is [array]) { $headerValue = $headerValue -join ', ' }
            Write-Action1Log "  $headerName`: $headerValue" -Level TRACE
        }
        $contentType = if ($response.Headers['Content-Type']) { $response.Headers['Content-Type'] } else { 'none' }
        Write-Action1Log "Content-Type: $contentType" -Level TRACE
        Write-Action1Log "Content-Length: $($response.Content.Length) bytes" -Level TRACE
        if ($response.Content) {
            Write-Action1Log "Response Body:" -Level TRACE
            Write-Action1Log $response.Content -Level TRACE
        }
        Write-Action1Log "===========================================" -Level TRACE

        Write-Action1Log "Upload init response status: $statusCode" -Level DEBUG

        if ($statusCode -ne 308) {
            Write-Action1Log "Upload init failed: expected 308, got $statusCode" -Level ERROR
            Write-Action1Log "Response: $($response.Content)" -Level ERROR
            throw "Upload initialization failed: expected HTTP 308, got $statusCode"
        }

        # Get the upload location from headers
        $uploadLocation = $response.Headers['X-Upload-Location']
        if (-not $uploadLocation) {
            $uploadLocation = $response.Headers['x-upload-location']
        }

        if (-not $uploadLocation) {
            Write-Action1Log "X-Upload-Location header missing from response" -Level ERROR
            Write-Action1Log "Available headers: $($response.Headers.Keys -join ', ')" -Level DEBUG
            throw "Upload initialization succeeded but X-Upload-Location header is missing"
        }

        # Handle array response (PowerShell may return headers as arrays)
        if ($uploadLocation -is [array]) {
            $uploadLocation = $uploadLocation[0]
        }

        # Normalize the upload URL
        $normalizedUrl = Get-UploadLocationUrl -BaseUri $script:Action1BaseUri -Location $uploadLocation

        Write-Action1Log "Upload URL obtained: $normalizedUrl" -Level INFO

        return $normalizedUrl
    }
    catch {
        Write-Action1Log "Upload initialization failed" -Level ERROR -ErrorRecord $_
        throw
    }
}

function Invoke-Action1SoftwareRepoUpload {
    <#
    .SYNOPSIS
        Uploads a file to Action1 software repository using resumable upload protocol.

    .DESCRIPTION
        Implements the Action1 resumable upload protocol:
        1. Initializes upload session (POST with X-Upload-Content-* headers)
        2. Uploads file in chunks using Content-Range headers
        3. Each chunk expects HTTP 308 (continue) or 200/201/204 (complete)

        This is the correct upload method for Action1 software repository,
        matching the protocol used by the official zsh deployment script.

    .PARAMETER FilePath
        Path to the file to upload.

    .PARAMETER OrganizationId
        The organization ID (or "all" for enterprise-wide).

    .PARAMETER PackageId
        The software repository package ID.

    .PARAMETER VersionId
        The version ID to upload to.

    .PARAMETER Platform
        The platform identifier. Valid values:
        - Windows_64, Windows_32, Windows_ARM64
        - Mac_AppleSilicon, Mac_IntelCPU

    .PARAMETER ChunkSizeMB
        Size of each upload chunk in megabytes. Default is 24MB.
        Minimum is 5MB.

    .PARAMETER ProgressId
        The progress bar ID for this upload. Default is 1.
        Use different IDs for parallel uploads.

    .PARAMETER ProgressState
        A synchronized hashtable for sharing progress state across parallel uploads.
        Used by Invoke-Action1MultiFileUpload.

    .PARAMETER ShowProgress
        Whether to show progress bars. Default is true.

    .EXAMPLE
        Invoke-Action1SoftwareRepoUpload -FilePath "C:\installer.msi" `
            -OrganizationId "all" -PackageId "pkg123" -VersionId "ver456" `
            -Platform "Windows_64"

    .EXAMPLE
        # Upload a Mac installer
        Invoke-Action1SoftwareRepoUpload -FilePath "/path/to/app.zip" `
            -OrganizationId "org789" -PackageId "pkg123" -VersionId "ver456" `
            -Platform "Mac_AppleSilicon" -ChunkSizeMB 32
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$OrganizationId,

        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
        [string]$VersionId,

        [Parameter(Mandatory)]
        [ValidateSet('Windows_64', 'Windows_32', 'Windows_ARM64', 'Mac_AppleSilicon', 'Mac_IntelCPU')]
        [string]$Platform,

        [Parameter()]
        [ValidateRange(5, 100)]
        [int]$ChunkSizeMB = 24,

        [Parameter()]
        [int]$ProgressId = 1,

        [Parameter()]
        [hashtable]$ProgressState,

        [Parameter()]
        [bool]$ShowProgress = $true,

        [Parameter()]
        [hashtable]$OverallContext
    )

    # Validate file exists
    if (-not (Test-Path $FilePath)) {
        throw "File not found: $FilePath"
    }

    $fileInfo = Get-Item $FilePath
    $fileSize = $fileInfo.Length
    $fileName = $fileInfo.Name
    $chunkSize = $ChunkSizeMB * 1024 * 1024
    $totalChunks = [Math]::Ceiling($fileSize / $chunkSize)

    # Platform display name for progress
    $platformDisplay = switch ($Platform) {
        'Windows_64' { 'x64' }
        'Windows_32' { 'x86' }
        'Windows_ARM64' { 'ARM64' }
        'Mac_AppleSilicon' { 'Apple Silicon' }
        'Mac_IntelCPU' { 'Intel' }
        default { $Platform }
    }

    Write-Action1Log "Starting software repository upload" -Level INFO
    Write-Action1Log "File: $fileName, Size: $(ConvertTo-FileSize -Bytes $fileSize), Chunks: $totalChunks x ${ChunkSizeMB}MB" -Level INFO

    # Initialize progress state if provided
    if ($ProgressState) {
        $ProgressState[$Platform] = @{
            FileName = $fileName
            FileSize = $fileSize
            BytesUploaded = 0
            ChunkNumber = 0
            TotalChunks = $totalChunks
            Status = 'Initializing'
            Speed = 0
            StartTime = Get-Date
        }
    }

    try {
        # Step 1: Initialize upload session
        if ($ShowProgress) {
            Write-Action1Progress -Activity "[$platformDisplay] $fileName" -Status "Initializing upload..." -PercentComplete 0 -Id $ProgressId
        }

        $uploadUrl = Initialize-Action1SoftwareRepoUpload `
            -OrganizationId $OrganizationId `
            -PackageId $PackageId `
            -VersionId $VersionId `
            -Platform $Platform `
            -FileSize $fileSize

        Write-Action1Log "Upload session initialized, URL: $uploadUrl" -Level DEBUG

        # Step 2: Upload file in chunks
        $token = Get-Action1AccessToken
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        $buffer = New-Object byte[] $chunkSize
        $offset = 0
        $chunkNumber = 0
        $uploadComplete = $false
        $uploadStartTime = Get-Date

        try {
            while ($offset -lt $fileSize) {
                $chunkNumber++
                $bytesToRead = [Math]::Min($chunkSize, $fileSize - $offset)
                $bytesRead = $fileStream.Read($buffer, 0, $bytesToRead)

                $startByte = $offset
                $endByte = $offset + $bytesRead - 1
                $contentRange = "bytes $startByte-$endByte/$fileSize"

                # Calculate progress and speed
                $percentComplete = [int](($offset / $fileSize) * 100)
                $uploadedSize = ConvertTo-FileSize -Bytes $offset
                $totalSize = ConvertTo-FileSize -Bytes $fileSize
                $elapsed = (Get-Date) - $uploadStartTime
                $speed = if ($elapsed.TotalSeconds -gt 0) { $offset / $elapsed.TotalSeconds } else { 0 }
                $speedDisplay = ConvertTo-FileSize -Bytes $speed
                $remaining = if ($speed -gt 0) { ($fileSize - $offset) / $speed } else { 0 }
                $remainingDisplay = if ($remaining -gt 60) { "{0:N0}m {1:N0}s" -f [Math]::Floor($remaining / 60), ($remaining % 60) } else { "{0:N0}s" -f $remaining }

                # Update progress state if provided
                if ($ProgressState) {
                    $ProgressState[$Platform].BytesUploaded = $offset
                    $ProgressState[$Platform].ChunkNumber = $chunkNumber
                    $ProgressState[$Platform].Status = 'Uploading'
                    $ProgressState[$Platform].Speed = $speed
                }

                if ($ShowProgress) {
                    Write-Action1Progress `
                        -Activity "[$platformDisplay] $fileName" `
                        -Status "Chunk $chunkNumber/$totalChunks | $uploadedSize / $totalSize | $speedDisplay/s | ETA: $remainingDisplay" `
                        -PercentComplete $percentComplete `
                        -Id $ProgressId
                }

                Write-Action1Log "Uploading chunk $($chunkNumber)/$($totalChunks): $contentRange (chunk bytes: $bytesRead, total file: $fileSize)" -Level DEBUG

                # Prepare the chunk data
                $chunkData = New-Object byte[] $bytesRead
                [Array]::Copy($buffer, 0, $chunkData, 0, $bytesRead)

                $chunkHeaders = @{
                    'Authorization'  = "Bearer $token"
                    'Content-Type'   = 'application/octet-stream'
                    'Content-Range'  = $contentRange
                }

                # TRACE: Log full chunk request details
                Write-Action1Log "========== CHUNK $chunkNumber REQUEST ==========" -Level TRACE
                Write-Action1Log "PUT $uploadUrl" -Level TRACE
                Write-Action1Log "Request Headers:" -Level TRACE
                Write-Action1Log "  Authorization: Bearer ***MASKED***" -Level TRACE
                Write-Action1Log "  Content-Type: $($chunkHeaders['Content-Type'])" -Level TRACE
                Write-Action1Log "  Content-Range: $($chunkHeaders['Content-Range'])" -Level TRACE
                Write-Action1Log "Request Body: <binary data, $bytesRead bytes>" -Level TRACE
                Write-Action1Log "===============================================" -Level TRACE

                # Upload chunk with real-time progress
                $progressParams = @{
                    Activity = "[$platformDisplay] $fileName"
                    Id = $ProgressId
                    FileOffset = $offset
                    FileSize = $fileSize
                    ChunkNumber = $chunkNumber
                    TotalChunks = $totalChunks
                    UploadStartTime = $uploadStartTime
                    OverallContext = $OverallContext
                }

                $response = Send-ChunkWithProgress `
                    -Uri $uploadUrl `
                    -Headers $chunkHeaders `
                    -Data $chunkData `
                    -ProgressParams $progressParams `
                    -ShowProgress $ShowProgress

                $statusCode = $response.StatusCode
                $statusDescription = $response.StatusDescription

                # TRACE: Log full chunk response details
                Write-Action1Log "========== CHUNK $chunkNumber RESPONSE ==========" -Level TRACE
                Write-Action1Log "HTTP Status: $statusCode $statusDescription" -Level TRACE
                Write-Action1Log "Duration: $($response.ElapsedMilliseconds)ms" -Level TRACE
                Write-Action1Log "Response Headers:" -Level TRACE
                foreach ($headerName in $response.Headers.Keys) {
                    $headerValue = $response.Headers[$headerName]
                    Write-Action1Log "  $headerName`: $headerValue" -Level TRACE
                }
                $respContentType = if ($response.Headers['Content-Type']) { $response.Headers['Content-Type'] } else { 'none' }
                Write-Action1Log "Content-Type: $respContentType" -Level TRACE
                if ($response.Content -and $response.Content.Length -gt 0) {
                    Write-Action1Log "Response Body:" -Level TRACE
                    Write-Action1Log $response.Content -Level TRACE
                }
                Write-Action1Log "================================================" -Level TRACE

                # Log response details for debugging
                $rangeHeader = $response.Headers['Range']
                Write-Action1Log "Chunk $chunkNumber response: Status=$statusCode, Range=$rangeHeader" -Level DEBUG

                # Check response status
                if ($statusCode -eq 308) {
                    # Continue uploading - 308 means server received data but expects more
                    Write-Action1Log "Chunk $chunkNumber uploaded successfully (308 - continue)" -Level DEBUG
                }
                elseif ($statusCode -in @(200, 201, 204)) {
                    # Upload complete
                    Write-Action1Log "Chunk $chunkNumber uploaded - upload complete ($statusCode)" -Level INFO
                    $uploadComplete = $true
                    break
                }
                else {
                    $errorContent = $response.Content
                    Write-Action1Log "Chunk upload failed with status $statusCode`: $errorContent" -Level ERROR
                    throw "Chunk upload failed with status code: $statusCode"
                }

                $offset += $bytesRead
            }
        }
        finally {
            $fileStream.Close()
            $fileStream.Dispose()
        }

        # Update final progress state
        if ($ProgressState) {
            $ProgressState[$Platform].BytesUploaded = $fileSize
            $ProgressState[$Platform].Status = if ($uploadComplete) { 'Complete' } else { 'Warning' }
        }

        # Check if upload actually completed
        if (-not $uploadComplete) {
            Write-Action1Log "WARNING: All chunks uploaded but server did not confirm completion (expected 200, got 308 on all chunks)" -Level WARN
            Write-Host "⚠ Upload may be incomplete: $fileName - server did not confirm completion" -ForegroundColor Yellow
        }

        if ($ShowProgress) {
            Write-Action1Progress -Activity "[$platformDisplay] $fileName" -Status "Complete" -PercentComplete 100 -Id $ProgressId
            Start-Sleep -Milliseconds 300
            Write-Progress -Activity "[$platformDisplay] $fileName" -Id $ProgressId -Completed
        }

        Write-Action1Log "Software repository upload completed successfully" -Level INFO

        return @{
            Success = $true
            FileName = $fileName
            FileSize = $fileSize
            ChunksUploaded = $chunkNumber
            Platform = $Platform
            Duration = ((Get-Date) - $uploadStartTime).TotalSeconds
        }
    }
    catch {
        if ($ShowProgress) {
            Write-Progress -Activity "[$platformDisplay] $fileName" -Id $ProgressId -Completed
        }
        if ($ProgressState) {
            $ProgressState[$Platform].Status = 'Failed'
        }
        Write-Action1Log "Software repository upload failed" -Level ERROR -ErrorRecord $_
        throw
    }
}

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

#endregion

#region Helper Functions

function Send-ChunkWithProgress {
    <#
    .SYNOPSIS
        Uploads a chunk using HttpClient with progress estimation during transfer.

    .DESCRIPTION
        Uses .NET HttpClient to upload data while providing estimated progress
        updates during the transfer. Since HttpClient doesn't provide true
        byte-level progress callbacks, this function estimates progress based
        on elapsed time and updates the progress bar smoothly.

    .PARAMETER Uri
        The URI to send the request to.

    .PARAMETER Headers
        Hashtable of headers to include (Authorization, Content-Range, etc.).

    .PARAMETER Data
        The byte array data to send.

    .PARAMETER ProgressParams
        Hashtable with progress display parameters:
        - Activity: Progress bar activity text
        - Id: Progress bar ID
        - FileOffset: Current offset in the overall file
        - FileSize: Total file size
        - ChunkNumber: Current chunk number
        - TotalChunks: Total number of chunks
        - UploadStartTime: DateTime when upload started

    .PARAMETER ShowProgress
        Whether to show progress bar updates.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [hashtable]$Headers,

        [Parameter(Mandatory)]
        [byte[]]$Data,

        [Parameter()]
        [hashtable]$ProgressParams,

        [Parameter()]
        [bool]$ShowProgress = $true
    )

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromMinutes(30)

    $dataStream = $null
    $content = $null
    $request = $null

    try {
        # Create the request
        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Put, $Uri)

        # Add headers (except Content-Type which goes on content)
        foreach ($key in $Headers.Keys) {
            if ($key -notin @('Content-Type', 'Content-Range')) {
                $null = $request.Headers.TryAddWithoutValidation($key, $Headers[$key])
            }
        }

        # Create content from data
        $dataStream = [System.IO.MemoryStream]::new($Data)
        $content = [System.Net.Http.StreamContent]::new($dataStream)

        # Set content headers
        $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
        if ($Headers['Content-Range']) {
            $null = $content.Headers.TryAddWithoutValidation('Content-Range', $Headers['Content-Range'])
        }

        $request.Content = $content

        $chunkSize = $Data.Length
        $chunkStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Start async upload
        $sendTask = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)

        # Animate progress while uploading
        $animationChars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
        $animIndex = 0

        # For first chunk or when we don't have speed data, estimate based on time within chunk
        # Assume ~2 MB/s baseline speed if no history (conservative estimate)
        $baselineSpeed = 2 * 1024 * 1024

        while (-not $sendTask.IsCompleted) {
            if ($ShowProgress -and $ProgressParams) {
                $totalElapsed = (Get-Date) - $ProgressParams.UploadStartTime
                $chunkElapsed = $chunkStopwatch.ElapsedMilliseconds / 1000.0

                # Calculate historical speed if we have prior data
                $historicalSpeed = if ($totalElapsed.TotalSeconds -gt 0 -and $ProgressParams.FileOffset -gt 0) {
                    $ProgressParams.FileOffset / $totalElapsed.TotalSeconds
                } else {
                    $baselineSpeed
                }

                # Estimate progress within this chunk
                # Use time-based animation: smoothly progress through the chunk
                # Estimate how long the chunk should take based on speed
                $estimatedChunkDuration = if ($historicalSpeed -gt 0) { $chunkSize / $historicalSpeed } else { 10 }
                $chunkProgress = [Math]::Min(0.95, $chunkElapsed / [Math]::Max(0.5, $estimatedChunkDuration))

                $estimatedChunkBytes = [long]($chunkSize * $chunkProgress)
                $estimatedTotalBytes = $ProgressParams.FileOffset + $estimatedChunkBytes

                $percentComplete = [int](($estimatedTotalBytes / $ProgressParams.FileSize) * 100)
                $percentComplete = [Math]::Max(1, [Math]::Min(99, $percentComplete))  # Keep between 1-99% during transfer

                $uploadedDisplay = ConvertTo-FileSize -Bytes ([long]$estimatedTotalBytes)
                $totalDisplay = ConvertTo-FileSize -Bytes $ProgressParams.FileSize

                # Show current speed estimate (if we have any data, otherwise show "calculating...")
                $currentSpeed = if ($chunkElapsed -gt 0.5) { $estimatedChunkBytes / $chunkElapsed } else { $historicalSpeed }
                $speedDisplay = if ($totalElapsed.TotalSeconds -lt 0.5 -and $ProgressParams.FileOffset -eq 0) {
                    "calculating..."
                } else {
                    "$(ConvertTo-FileSize -Bytes $currentSpeed)/s"
                }

                $remaining = if ($currentSpeed -gt 0) { ($ProgressParams.FileSize - $estimatedTotalBytes) / $currentSpeed } else { 0 }
                $remainingDisplay = if ($remaining -gt 60) { "{0:N0}m {1:N0}s" -f [Math]::Floor($remaining / 60), ($remaining % 60) } else { "{0:N0}s" -f $remaining }

                $spinner = $animationChars[$animIndex % $animationChars.Count]
                $animIndex++

                # Update file progress bar
                Write-Action1Progress `
                    -Activity $ProgressParams.Activity `
                    -Status "$spinner Chunk $($ProgressParams.ChunkNumber)/$($ProgressParams.TotalChunks) | $uploadedDisplay / $totalDisplay | $speedDisplay | ETA: $remainingDisplay" `
                    -PercentComplete $percentComplete `
                    -Id $ProgressParams.Id

                # Update overall progress bar if multi-file context provided
                if ($ProgressParams.OverallContext) {
                    $oc = $ProgressParams.OverallContext
                    $overallElapsed = (Get-Date) - $oc.StartTime
                    $overallEstimatedBytes = $oc.PriorBytes + $estimatedTotalBytes
                    $overallPercent = [int](($overallEstimatedBytes / $oc.TotalSize) * 100)
                    $overallPercent = [Math]::Max(1, [Math]::Min(99, $overallPercent))
                    $overallSpeed = if ($overallElapsed.TotalSeconds -gt 0) { $overallEstimatedBytes / $overallElapsed.TotalSeconds } else { $currentSpeed }
                    $overallSpeedDisplay = "$(ConvertTo-FileSize -Bytes $overallSpeed)/s"

                    Write-Action1Progress `
                        -Activity "Overall: $($oc.FileIndex) of $($oc.TotalFiles) files" `
                        -Status "$spinner $(ConvertTo-FileSize -Bytes $overallEstimatedBytes) / $(ConvertTo-FileSize -Bytes $oc.TotalSize) | $overallSpeedDisplay" `
                        -PercentComplete $overallPercent `
                        -Id 0
                }
            }

            Start-Sleep -Milliseconds 100
        }

        $chunkStopwatch.Stop()

        # Get the response
        $response = $sendTask.GetAwaiter().GetResult()

        # Read response content
        $responseContent = ""
        if ($response.Content) {
            $responseContent = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }

        # Build response headers hashtable
        $responseHeaders = @{}
        foreach ($header in $response.Headers) {
            $responseHeaders[$header.Key] = ($header.Value -join ', ')
        }
        if ($response.Content -and $response.Content.Headers) {
            foreach ($header in $response.Content.Headers) {
                $responseHeaders[$header.Key] = ($header.Value -join ', ')
            }
        }

        return @{
            StatusCode = [int]$response.StatusCode
            StatusDescription = $response.ReasonPhrase
            Content = $responseContent
            Headers = $responseHeaders
            ElapsedMilliseconds = $chunkStopwatch.ElapsedMilliseconds
        }
    }
    finally {
        if ($dataStream) { $dataStream.Dispose() }
        if ($content) { $content.Dispose() }
        if ($request) { $request.Dispose() }
        $client.Dispose()
        $handler.Dispose()
    }
}

function Get-AppNameMatchPatterns {
    <#
    .SYNOPSIS
        Generates regex patterns for matching application display names.

    .DESCRIPTION
        Creates two patterns for the Action1 app_name_match field:
        - Specific: Matches the exact app name with version placeholder
        - Broad: Matches variations of the app name

    .PARAMETER AppName
        The application name to generate patterns for.

    .OUTPUTS
        Returns a hashtable with Specific and Broad regex patterns.

    .EXAMPLE
        Get-AppNameMatchPatterns -AppName "PowerShell 7 Preview"
        # Returns: @{ Specific = "^PowerShell 7 Preview.*$"; Broad = "^PowerShell.*Preview.*$" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName
    )

    # Escape regex special characters in the app name
    $escapedName = [regex]::Escape($AppName)

    # Specific pattern: exact name followed by optional version info
    $specificPattern = "^$escapedName.*`$"

    # Broad pattern: key words from the app name with wildcards between
    # Extract significant words (3+ characters, not common words)
    $commonWords = @('the', 'and', 'for', 'with', 'from')
    $words = $AppName -split '\s+' | Where-Object {
        $_.Length -ge 3 -and $_ -notin $commonWords
    }

    if ($words.Count -gt 0) {
        # Join words with .* to create a broad match
        $escapedWords = $words | ForEach-Object { [regex]::Escape($_) }
        $broadPattern = "^" + ($escapedWords -join '.*') + ".*`$"
    }
    else {
        # Fallback to escaped name
        $broadPattern = "^$escapedName.*`$"
    }

    return @{
        Specific = $specificPattern
        Broad    = $broadPattern
    }
}

function Get-Action1AccessToken {
    <#
    .SYNOPSIS
        Obtains an OAuth2 access token from the Action1 API.
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    # Check if we have a valid token already
    if (-not $Force -and $script:Action1AccessToken -and $script:Action1TokenExpiry -and (Get-Date) -lt $script:Action1TokenExpiry) {
        Write-Action1Log "Using cached access token (expires: $($script:Action1TokenExpiry))" -Level DEBUG
        return $script:Action1AccessToken
    }

    if (-not $script:Action1ClientId -or -not $script:Action1ClientSecret) {
        Write-Action1Log "API credentials not configured" -Level ERROR
        throw "Action1 API credentials not set. Please run Set-Action1ApiCredentials first."
    }

    if (-not $script:Action1BaseUri) {
        Write-Action1Log "API base URI not configured" -Level ERROR
        throw "Action1 API base URI not set. Please run Set-Action1ApiCredentials first."
    }

    Write-Action1Log "Requesting OAuth2 access token..." -Level INFO

    $tokenUrl = "$($script:Action1BaseUri)/oauth2/token"
    $body = @{
        client_id     = $script:Action1ClientId
        client_secret = $script:Action1ClientSecret
    }

    # TRACE logging for token request (mask sensitive data)
    Write-Action1Log "Token request URL: $tokenUrl" -Level TRACE
    Write-Action1Log "Token request body" -Level TRACE -Data @{
        client_id     = $script:Action1ClientId
        client_secret = "***MASKED***"
    }

    try {
        $bodyJson = $body | ConvertTo-Json

        # TRACE: Log full request details
        Write-Action1Log "========== TOKEN REQUEST ==========" -Level TRACE
        Write-Action1Log "POST $tokenUrl" -Level TRACE
        Write-Action1Log "Content-Type: application/json" -Level TRACE
        Write-Action1Log "Request Body: $($bodyJson -replace $script:Action1ClientSecret, '***MASKED***')" -Level TRACE
        Write-Action1Log "===================================" -Level TRACE

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Use Invoke-WebRequest for full HTTP details
        $webResponse = Invoke-WebRequest -Uri $tokenUrl -Method POST -Body $bodyJson -ContentType 'application/json' -ErrorAction Stop

        $stopwatch.Stop()
        $statusCode = $webResponse.StatusCode
        $statusDescription = $webResponse.StatusDescription

        # TRACE: Log full response details
        Write-Action1Log "========== TOKEN RESPONSE ==========" -Level TRACE
        Write-Action1Log "HTTP Status: $statusCode $statusDescription" -Level TRACE
        Write-Action1Log "Duration: $($stopwatch.ElapsedMilliseconds)ms" -Level TRACE

        # Log response headers
        Write-Action1Log "Response Headers:" -Level TRACE
        foreach ($headerName in $webResponse.Headers.Keys) {
            $headerValue = $webResponse.Headers[$headerName]
            if ($headerValue -is [array]) { $headerValue = $headerValue -join ', ' }
            Write-Action1Log "  $headerName`: $headerValue" -Level TRACE
        }

        # Log content details (mask token in raw output)
        $contentType = if ($webResponse.Headers['Content-Type']) { $webResponse.Headers['Content-Type'] } else { 'unknown' }
        Write-Action1Log "Content-Type: $contentType" -Level TRACE
        Write-Action1Log "Content-Length: $($webResponse.Content.Length) bytes" -Level TRACE
        Write-Action1Log "Response Body (raw, token masked):" -Level TRACE
        $maskedContent = $webResponse.Content -replace '"access_token"\s*:\s*"[^"]+', '"access_token":"***MASKED***'
        Write-Action1Log $maskedContent -Level TRACE
        Write-Action1Log "====================================" -Level TRACE

        # Parse response
        $response = $webResponse.Content | ConvertFrom-Json

        Write-Action1Log "Token response (parsed, masked)" -Level TRACE -Data @{
            access_token = "***MASKED*** (length: $($response.access_token.Length))"
            expires_in   = $response.expires_in
            token_type   = $response.token_type
        }

        $script:Action1AccessToken = $response.access_token

        # Set token expiry (default to 1 hour if not provided, subtract 5 minutes for safety)
        $expiresIn = if ($response.expires_in) { $response.expires_in - 300 } else { 3300 }
        $script:Action1TokenExpiry = (Get-Date).AddSeconds($expiresIn)

        Write-Action1Log "Access token obtained successfully (expires in $expiresIn seconds)" -Level INFO
        return $script:Action1AccessToken
    }
    catch {
        Write-Action1Log "Failed to obtain access token" -Level ERROR -ErrorRecord $_

        # TRACE: Log error details
        if ($_.Exception.Response) {
            $errorResponse = $_.Exception.Response
            Write-Action1Log "========== TOKEN ERROR RESPONSE ==========" -Level TRACE
            Write-Action1Log "HTTP Status: $([int]$errorResponse.StatusCode) $($errorResponse.StatusCode)" -Level TRACE
            try {
                $reader = [System.IO.StreamReader]::new($errorResponse.GetResponseStream())
                $errorBody = $reader.ReadToEnd()
                $reader.Close()
                Write-Action1Log "Error Response Body:" -Level TRACE
                Write-Action1Log $errorBody -Level TRACE
            }
            catch {
                Write-Action1Log "Could not read error response body" -Level TRACE
            }
            Write-Action1Log "===========================================" -Level TRACE
        }

        throw "Authentication failed: $($_.Exception.Message)"
    }
}

function Get-Action1Headers {
    [CmdletBinding()]
    param()

    Write-Action1Log "Generating authentication headers" -Level TRACE

    # Get or refresh the access token
    $token = Get-Action1AccessToken

    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }

    # TRACE logging for headers (mask sensitive data)
    Write-Action1Log "Request headers" -Level TRACE -Data @{
        'Authorization' = "Bearer ***MASKED*** (length: $($token.Length))"
        'Content-Type'  = $headers['Content-Type']
        'Accept'        = $headers['Accept']
    }

    Write-Action1Log "Authentication headers generated successfully" -Level DEBUG

    return $headers
}

function Invoke-Action1ApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,
        
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'PATCH')]
        [string]$Method,
        
        [Parameter()]
        [hashtable]$Body,
        
        [Parameter()]
        [hashtable]$QueryParameters
    )
    
    $headers = Get-Action1Headers
    $uri = "$script:Action1BaseUri/$Endpoint"

    if ($QueryParameters) {
        $queryString = ($QueryParameters.GetEnumerator() | ForEach-Object {
            "$($_.Key)=$([uri]::EscapeDataString($_.Value))"
        }) -join '&'
        $uri = "$uri`?$queryString"
    }

    Write-Action1Log "Preparing API request: $Method $uri" -Level DEBUG

    # TRACE: Log complete request details
    Write-Action1Log "Request endpoint: $Endpoint" -Level TRACE
    Write-Action1Log "Request full URI: $uri" -Level TRACE
    Write-Action1Log "Request method: $Method" -Level TRACE
    if ($QueryParameters) {
        Write-Action1Log "Query parameters" -Level TRACE -Data $QueryParameters
    }

    $params = @{
        Uri = $uri
        Method = $Method
        Headers = $headers
        ErrorAction = 'Stop'
    }

    $bodyJson = $null
    if ($Body) {
        $bodyJson = ($Body | ConvertTo-Json -Depth 10)
        $params['Body'] = $bodyJson
        Write-Action1Log "Request body (raw JSON)" -Level TRACE
        Write-Action1Log $bodyJson -Level TRACE
        Write-Action1Log "Request body (parsed)" -Level TRACE -Data $Body
    } else {
        Write-Action1Log "Request body: (none)" -Level TRACE
    }

    # TRACE: Log complete request summary
    Write-Action1Log "--- REQUEST SUMMARY ---" -Level TRACE
    Write-Action1Log "$Method $uri" -Level TRACE
    Write-Action1Log "Content-Type: application/json" -Level TRACE
    Write-Action1Log "Body size: $(if ($bodyJson) { $bodyJson.Length } else { 0 }) bytes" -Level TRACE
    Write-Action1Log "-----------------------" -Level TRACE

    try {
        Write-Action1Log "Executing API request..." -Level INFO
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Use Invoke-WebRequest for full HTTP details at TRACE level
        $webResponse = Invoke-WebRequest @params

        $stopwatch.Stop()
        $statusCode = $webResponse.StatusCode
        $statusDescription = $webResponse.StatusDescription

        Write-Action1Log "API request completed: HTTP $statusCode in $($stopwatch.ElapsedMilliseconds)ms" -Level INFO

        # TRACE: Log complete response details
        Write-Action1Log "========== RESPONSE ==========" -Level TRACE
        Write-Action1Log "HTTP Status: $statusCode $statusDescription" -Level TRACE
        Write-Action1Log "Duration: $($stopwatch.ElapsedMilliseconds)ms" -Level TRACE

        # Log all response headers
        Write-Action1Log "Response Headers:" -Level TRACE
        foreach ($headerName in $webResponse.Headers.Keys) {
            $headerValue = $webResponse.Headers[$headerName]
            if ($headerValue -is [array]) { $headerValue = $headerValue -join ', ' }
            Write-Action1Log "  $headerName`: $headerValue" -Level TRACE
        }

        # Log content details
        $contentLength = if ($webResponse.Headers['Content-Length']) { $webResponse.Headers['Content-Length'] } else { $webResponse.Content.Length }
        $contentType = if ($webResponse.Headers['Content-Type']) { $webResponse.Headers['Content-Type'] } else { 'unknown' }
        Write-Action1Log "Content-Type: $contentType" -Level TRACE
        Write-Action1Log "Content-Length: $contentLength bytes" -Level TRACE

        # Log raw response body
        Write-Action1Log "Response Body (raw):" -Level TRACE
        Write-Action1Log $webResponse.Content -Level TRACE
        Write-Action1Log "================================" -Level TRACE

        # Parse JSON response
        $response = $webResponse.Content | ConvertFrom-Json

        # Also log parsed data
        Write-Action1Log "Response data (parsed)" -Level TRACE -Data $response

        return $response
    }
    catch {
        $stopwatch.Stop()
        Write-Action1Log "API request failed after $($stopwatch.ElapsedMilliseconds)ms" -Level ERROR -ErrorRecord $_

        # Try to extract more details from the exception
        if ($_.Exception.Response) {
            $errorResponse = $_.Exception.Response
            Write-Action1Log "========== ERROR RESPONSE ==========" -Level TRACE
            Write-Action1Log "HTTP Status: $([int]$errorResponse.StatusCode) $($errorResponse.StatusCode)" -Level TRACE
            Write-Action1Log "Status Description: $($errorResponse.ReasonPhrase)" -Level TRACE

            # Try to read error response body
            try {
                $reader = [System.IO.StreamReader]::new($errorResponse.GetResponseStream())
                $errorBody = $reader.ReadToEnd()
                $reader.Close()
                Write-Action1Log "Error Response Body:" -Level TRACE
                Write-Action1Log $errorBody -Level TRACE
            }
            catch {
                Write-Action1Log "Could not read error response body: $_" -Level TRACE
            }
            Write-Action1Log "=====================================" -Level TRACE
        }

        if ($_.ErrorDetails.Message) {
            Write-Action1Log "Error details from API" -Level ERROR -Data ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue)
        }

        throw
    }
}

function Format-NestedObject {
    <#
    .SYNOPSIS
        Formats a nested object or array into a readable indented string.

    .DESCRIPTION
        Helper function that converts complex nested objects into human-readable
        indented text format for display purposes.

    .PARAMETER Object
        The object to format.

    .PARAMETER Indent
        The current indentation level (used for recursion).

    .PARAMETER IndentString
        The string to use for each indentation level.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Object,

        [Parameter()]
        [int]$Indent = 0,

        [Parameter()]
        [string]$IndentString = '    '
    )

    if ($null -eq $Object) {
        return ''
    }

    $prefix = $IndentString * $Indent
    $lines = @()

    # Handle arrays
    if ($Object -is [System.Collections.IEnumerable] -and $Object -isnot [string] -and $Object -isnot [System.Collections.IDictionary]) {
        $index = 0
        foreach ($item in $Object) {
            if ($item -is [PSCustomObject] -or $item -is [System.Collections.IDictionary]) {
                $lines += "${prefix}[$index]:"
                $lines += Format-NestedObject -Object $item -Indent ($Indent + 1) -IndentString $IndentString
            }
            else {
                $lines += "${prefix}[$index]: $item"
            }
            $index++
        }
    }
    # Handle PSCustomObject or hashtable
    elseif ($Object -is [PSCustomObject] -or $Object -is [System.Collections.IDictionary]) {
        $props = if ($Object -is [PSCustomObject]) { $Object.PSObject.Properties } else { $Object.GetEnumerator() }
        foreach ($prop in $props) {
            $name = if ($Object -is [PSCustomObject]) { $prop.Name } else { $prop.Key }
            $value = if ($Object -is [PSCustomObject]) { $prop.Value } else { $prop.Value }

            # Skip very long script content for cleaner display
            if ($name -match 'script_text|script_content' -and $value -is [string] -and $value.Length -gt 100) {
                $lines += "${prefix}${name}: <script content, $($value.Length) chars>"
                continue
            }

            if ($null -eq $value -or $value -eq '') {
                $lines += "${prefix}${name}: "
            }
            elseif ($value -is [PSCustomObject] -or $value -is [System.Collections.IDictionary]) {
                $lines += "${prefix}${name}:"
                $lines += Format-NestedObject -Object $value -Indent ($Indent + 1) -IndentString $IndentString
            }
            elseif ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                $lines += "${prefix}${name}:"
                $lines += Format-NestedObject -Object $value -Indent ($Indent + 1) -IndentString $IndentString
            }
            else {
                $lines += "${prefix}${name}: $value"
            }
        }
    }
    else {
        $lines += "${prefix}$Object"
    }

    return $lines -join "`n"
}

function Expand-NestedJsonAttributes {
    <#
    .SYNOPSIS
        Expands nested JSON attributes into flattened, user-friendly properties.

    .DESCRIPTION
        Takes an API response object and flattens nested structures like file_name
        (which contains platform-keyed objects) into readable properties.
        This function is designed to be reusable across multiple API response types.

    .PARAMETER InputObject
        The PSObject to expand. Can be a single object or an array.

    .PARAMETER ExpandFileNames
        If specified, expands the file_name property which contains platform-keyed objects.

    .PARAMETER FormatNested
        If specified, formats nested objects (like additional_actions) into readable indented strings.

    .EXAMPLE
        $version | Expand-NestedJsonAttributes -ExpandFileNames
        # Expands file_name: {Windows32: {name: "app.exe"}} into Files array

    .EXAMPLE
        Get-Action1AppPackage | Expand-NestedJsonAttributes -ExpandFileNames -FormatNested
        # Processes objects and formats nested attributes readably
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter()]
        [switch]$ExpandFileNames,

        [Parameter()]
        [switch]$FormatNested
    )

    process {
        if ($null -eq $InputObject) {
            return $null
        }

        # Handle arrays by processing each item
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string] -and $InputObject -isnot [System.Collections.IDictionary]) {
            foreach ($item in $InputObject) {
                Expand-NestedJsonAttributes -InputObject $item -ExpandFileNames:$ExpandFileNames -FormatNested:$FormatNested
            }
            return
        }

        # Clone the object to avoid modifying the original
        $expanded = [PSCustomObject]@{}

        foreach ($prop in $InputObject.PSObject.Properties) {
            $propName = $prop.Name
            $propValue = $prop.Value

            # Handle file_name expansion
            if ($ExpandFileNames -and $propName -eq 'file_name' -and $propValue -is [PSCustomObject]) {
                # Extract files from platform-keyed structure
                $files = @()
                foreach ($platformProp in $propValue.PSObject.Properties) {
                    $platform = $platformProp.Name
                    $fileInfo = $platformProp.Value

                    if ($fileInfo -is [PSCustomObject]) {
                        $files += [PSCustomObject]@{
                            Platform = $platform
                            FileName = $fileInfo.name
                            FileType = $fileInfo.type
                        }
                    }
                }

                # Add flattened Files array (formatted if requested)
                if ($FormatNested) {
                    $formattedFiles = Format-NestedObject -Object $files
                    $expanded | Add-Member -NotePropertyName 'Files' -NotePropertyValue $formattedFiles
                }
                else {
                    $expanded | Add-Member -NotePropertyName 'Files' -NotePropertyValue $files
                }

                # Add convenience properties (always plural for consistency)
                if ($files.Count -eq 1) {
                    $expanded | Add-Member -NotePropertyName 'FileNames' -NotePropertyValue $files[0].FileName
                    $expanded | Add-Member -NotePropertyName 'FileTypes' -NotePropertyValue $files[0].FileType
                    $expanded | Add-Member -NotePropertyName 'Platforms' -NotePropertyValue $files[0].Platform
                }
                elseif ($files.Count -gt 1) {
                    # For multi-platform, create arrays/summary strings
                    $expanded | Add-Member -NotePropertyName 'FileNames' -NotePropertyValue ($files.FileName -join '; ')
                    $expanded | Add-Member -NotePropertyName 'FileTypes' -NotePropertyValue (($files.FileType | Select-Object -Unique) -join ', ')
                    $expanded | Add-Member -NotePropertyName 'Platforms' -NotePropertyValue ($files.Platform -join ', ')
                }
            }
            # Handle binary_id similarly (it has the same platform-keyed structure)
            elseif ($ExpandFileNames -and $propName -eq 'binary_id' -and $propValue -is [PSCustomObject]) {
                $binaryIds = @()
                foreach ($platformProp in $propValue.PSObject.Properties) {
                    $binaryIds += [PSCustomObject]@{
                        Platform = $platformProp.Name
                        BinaryId = $platformProp.Value
                    }
                }
                if ($FormatNested) {
                    $formattedBinaryIds = Format-NestedObject -Object $binaryIds
                    $expanded | Add-Member -NotePropertyName 'BinaryIds' -NotePropertyValue $formattedBinaryIds
                }
                else {
                    $expanded | Add-Member -NotePropertyName 'BinaryIds' -NotePropertyValue $binaryIds
                }
            }
            # Handle additional_actions with friendly formatting
            elseif ($propName -eq 'additional_actions' -and $propValue -is [System.Collections.IEnumerable]) {
                # Create expanded actions with resolved names
                $expandedActions = @()
                foreach ($action in $propValue) {
                    # Try to resolve a friendly name from params
                    $friendlyName = $action.name
                    if ($action.params) {
                        if ($action.params.display_summary) {
                            $friendlyName = "$($action.name): $($action.params.display_summary)"
                        }
                        elseif ($action.params.run_script_id) {
                            # Extract name from run_script_id (e.g., "Check_System_Requirements_1768639966107" -> "Check System Requirements")
                            $scriptName = $action.params.run_script_id -replace '_\d+$', '' -replace '_', ' '
                            $friendlyName = "$($action.name): $scriptName"
                        }
                    }

                    # Build a cleaner action object
                    $cleanAction = [PSCustomObject]@{
                        Name       = $friendlyName
                        When       = $action.when
                        Priority   = $action.priority
                        TemplateId = $action.template_id
                        Id         = $action.id
                    }

                    # Add script info if available
                    if ($action.params.run_script_language) {
                        $cleanAction | Add-Member -NotePropertyName 'Language' -NotePropertyValue $action.params.run_script_language
                    }
                    if ($action.params.platform) {
                        $cleanAction | Add-Member -NotePropertyName 'Platform' -NotePropertyValue $action.params.platform
                    }

                    $expandedActions += $cleanAction
                }

                if ($FormatNested) {
                    # Format as readable string
                    $formattedOutput = Format-NestedObject -Object $expandedActions
                    $expanded | Add-Member -NotePropertyName 'AdditionalActions' -NotePropertyValue $formattedOutput
                }
                else {
                    $expanded | Add-Member -NotePropertyName 'AdditionalActions' -NotePropertyValue $expandedActions
                }
            }
            # Handle scoped_approvals with formatting
            elseif ($FormatNested -and $propName -eq 'scoped_approvals' -and $propValue -is [System.Collections.IEnumerable]) {
                $formattedOutput = Format-NestedObject -Object $propValue
                $expanded | Add-Member -NotePropertyName 'ScopedApprovals' -NotePropertyValue $formattedOutput
            }
            # Handle arrays of simple values (strings, numbers) - join them nicely
            elseif ($propValue -is [System.Collections.IEnumerable] -and $propValue -isnot [string]) {
                # Check if it's a simple array (all items are primitives)
                $isSimpleArray = $true
                $hasComplexItems = $false
                foreach ($item in $propValue) {
                    if ($item -is [PSCustomObject] -or ($item -is [System.Collections.IEnumerable] -and $item -isnot [string])) {
                        $hasComplexItems = $true
                        $isSimpleArray = $false
                        break
                    }
                }

                if ($isSimpleArray) {
                    # Simple array - join as comma-separated string for readability
                    $joined = ($propValue | ForEach-Object { "$_" }) -join ', '
                    $expanded | Add-Member -NotePropertyName $propName -NotePropertyValue $joined
                }
                elseif ($FormatNested -and $hasComplexItems) {
                    # Complex array with nested objects - format nicely
                    $formattedOutput = Format-NestedObject -Object $propValue
                    $expanded | Add-Member -NotePropertyName $propName -NotePropertyValue $formattedOutput
                }
                else {
                    # Keep as-is
                    $expanded | Add-Member -NotePropertyName $propName -NotePropertyValue $propValue
                }
            }
            # Handle other PSCustomObjects with FormatNested
            elseif ($FormatNested -and $propValue -is [PSCustomObject]) {
                # Format complex nested objects
                $formattedOutput = Format-NestedObject -Object $propValue
                $expanded | Add-Member -NotePropertyName $propName -NotePropertyValue $formattedOutput
            }
            else {
                # Copy other properties as-is
                $expanded | Add-Member -NotePropertyName $propName -NotePropertyValue $propValue
            }
        }

        return $expanded
    }
}

function Read-ManifestFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    Write-Action1Log "Reading manifest file: $Path" -Level DEBUG
    
    if (-not (Test-Path $Path)) {
        Write-Action1Log "Manifest file not found: $Path" -Level ERROR
        throw "Manifest file not found: $Path"
    }
    
    try {
        $manifest = Get-Content $Path -Raw | ConvertFrom-Json
        Write-Action1Log "Manifest loaded successfully" -Level INFO
        Write-Action1Log "Manifest contents" -Level TRACE -Data $manifest
        return $manifest
    }
    catch {
        Write-Action1Log "Failed to parse manifest file" -Level ERROR -ErrorRecord $_
        throw "Failed to parse manifest file: $($_.Exception.Message)"
    }
}

function Write-ManifestFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Manifest,
        
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    Write-Action1Log "Writing manifest to: $Path" -Level DEBUG
    Write-Action1Log "Manifest data to write" -Level TRACE -Data $Manifest
    
    try {
        $Manifest | ConvertTo-Json -Depth 10 | Set-Content $Path -Force
        Write-Action1Log "Manifest saved successfully" -Level INFO
    }
    catch {
        Write-Action1Log "Failed to save manifest file" -Level ERROR -ErrorRecord $_
        throw "Failed to save manifest file: $($_.Exception.Message)"
    }
}

#region Installer Metadata Extraction Functions

function Get-MsiMetadata {
    <#
    .SYNOPSIS
        Extracts metadata from MSI installer files by querying the MSI database.

    .DESCRIPTION
        Uses the WindowsInstaller.Installer COM object to query the Property table
        of an MSI file for ProductName, ProductVersion, Manufacturer, and other metadata.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Write-Action1Log "Attempting to extract MSI database metadata from: $Path" -Level DEBUG

    $result = @{
        Success = $false
        ProductName = $null
        ProductVersion = $null
        Manufacturer = $null
        Description = $null
        Source = "MSI Database"
    }

    try {
        $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $database = $windowsInstaller.GetType().InvokeMember(
            "OpenDatabase",
            [System.Reflection.BindingFlags]::InvokeMethod,
            $null,
            $windowsInstaller,
            @($Path, 0)  # 0 = msiOpenDatabaseModeReadOnly
        )

        # Query the Property table for metadata
        $propertyQuery = "SELECT Property, Value FROM Property WHERE Property IN ('ProductName', 'ProductVersion', 'Manufacturer', 'ARPCOMMENTS', 'ProductCode')"

        $view = $database.GetType().InvokeMember(
            "OpenView",
            [System.Reflection.BindingFlags]::InvokeMethod,
            $null,
            $database,
            @($propertyQuery)
        )

        $view.GetType().InvokeMember(
            "Execute",
            [System.Reflection.BindingFlags]::InvokeMethod,
            $null,
            $view,
            $null
        )

        $properties = @{}
        do {
            $record = $view.GetType().InvokeMember(
                "Fetch",
                [System.Reflection.BindingFlags]::InvokeMethod,
                $null,
                $view,
                $null
            )

            if ($null -ne $record) {
                $propertyName = $record.GetType().InvokeMember(
                    "StringData",
                    [System.Reflection.BindingFlags]::GetProperty,
                    $null,
                    $record,
                    @(1)
                )
                $propertyValue = $record.GetType().InvokeMember(
                    "StringData",
                    [System.Reflection.BindingFlags]::GetProperty,
                    $null,
                    $record,
                    @(2)
                )
                $properties[$propertyName] = $propertyValue
            }
        } while ($null -ne $record)

        $view.GetType().InvokeMember("Close", [System.Reflection.BindingFlags]::InvokeMethod, $null, $view, $null)

        # Release COM objects
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($view) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($database) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($windowsInstaller) | Out-Null

        if ($properties.Count -gt 0) {
            $result.ProductName = $properties['ProductName']
            $result.ProductVersion = $properties['ProductVersion']
            $result.Manufacturer = $properties['Manufacturer']
            $result.Description = $properties['ARPCOMMENTS']
            $result.Success = ($null -ne $result.ProductName -or $null -ne $result.ProductVersion)

            Write-Action1Log "MSI database metadata extracted successfully" -Level DEBUG -Data $properties
        }
    }
    catch {
        Write-Action1Log "Failed to extract MSI database metadata" -Level DEBUG -ErrorRecord $_
    }

    return $result
}

function Get-DigitalSignatureMetadata {
    <#
    .SYNOPSIS
        Extracts metadata from the digital signature/code signing certificate of an installer.

    .DESCRIPTION
        Parses the Authenticode signature to extract publisher information from the
        signing certificate's subject field.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Write-Action1Log "Attempting to extract digital signature metadata from: $Path" -Level DEBUG

    $result = @{
        Success = $false
        Publisher = $null
        Subject = $null
        Issuer = $null
        SignatureStatus = $null
        Source = "Digital Signature"
    }

    try {
        $signature = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop

        if ($signature.Status -ne 'NotSigned' -and $null -ne $signature.SignerCertificate) {
            $result.SignatureStatus = $signature.Status.ToString()
            $result.Subject = $signature.SignerCertificate.Subject
            $result.Issuer = $signature.SignerCertificate.Issuer

            # Parse the subject to extract organization/company name
            # Subject format: CN=Company Name, O=Organization, L=City, S=State, C=Country
            $subject = $signature.SignerCertificate.Subject

            # Try to extract O (Organization) first, then CN (Common Name)
            if ($subject -match 'O=([^,]+)') {
                $result.Publisher = $matches[1].Trim().Trim('"')
            }
            elseif ($subject -match 'CN=([^,]+)') {
                $result.Publisher = $matches[1].Trim().Trim('"')
            }

            $result.Success = ($null -ne $result.Publisher)

            Write-Action1Log "Digital signature metadata extracted" -Level DEBUG -Data @{
                Publisher = $result.Publisher
                Status = $result.SignatureStatus
                Subject = $result.Subject
            }
        }
        else {
            Write-Action1Log "File is not signed or signature is invalid" -Level DEBUG
        }
    }
    catch {
        Write-Action1Log "Failed to extract digital signature metadata" -Level DEBUG -ErrorRecord $_
    }

    return $result
}

function Get-InnoSetupMetadata {
    <#
    .SYNOPSIS
        Extracts metadata from Inno Setup installers.

    .DESCRIPTION
        Detects Inno Setup installers by signature and attempts to extract
        embedded setup information including AppName, AppVersion, AppPublisher.
        Uses binary pattern matching to find the embedded setup script data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Write-Action1Log "Attempting to extract Inno Setup metadata from: $Path" -Level DEBUG

    $result = @{
        Success = $false
        ProductName = $null
        ProductVersion = $null
        Publisher = $null
        InstallerType = $null
        Source = "Inno Setup"
    }

    try {
        # Read the first portion of the file to check for Inno Setup signatures
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $fileContent = [System.Text.Encoding]::ASCII.GetString($bytes[0..([Math]::Min(2MB, $bytes.Length - 1))])

        # Check for Inno Setup signatures
        $isInnoSetup = $false
        $innoSignatures = @(
            'Inno Setup',
            'InnoSetupVersion',
            'Inno Setup Setup Data',
            'inno.exe'
        )

        foreach ($sig in $innoSignatures) {
            if ($fileContent -match [regex]::Escape($sig)) {
                $isInnoSetup = $true
                $result.InstallerType = "Inno Setup"
                break
            }
        }

        if (-not $isInnoSetup) {
            Write-Action1Log "File does not appear to be an Inno Setup installer" -Level DEBUG
            return $result
        }

        Write-Action1Log "Inno Setup signature detected, extracting metadata..." -Level DEBUG

        # Try to find embedded script data patterns
        # Inno Setup stores strings in a specific format, often with null-terminated or length-prefixed strings

        # Look for common Inno Setup script patterns in the binary
        $patterns = @{
            'AppName' = 'AppName=([^\x00\r\n]+)'
            'AppVersion' = 'AppVersion=([^\x00\r\n]+)'
            'AppVerName' = 'AppVerName=([^\x00\r\n]+)'
            'AppPublisher' = 'AppPublisher=([^\x00\r\n]+)'
            'AppPublisherURL' = 'AppPublisherURL=([^\x00\r\n]+)'
            'DefaultDirName' = 'DefaultDirName=([^\x00\r\n]+)'
        }

        $foundValues = @{}
        foreach ($key in $patterns.Keys) {
            if ($fileContent -match $patterns[$key]) {
                $value = $matches[1].Trim()
                # Clean up the value - remove any binary garbage
                $value = $value -replace '[^\x20-\x7E]', ''
                if ($value.Length -gt 0 -and $value.Length -lt 200) {
                    $foundValues[$key] = $value
                }
            }
        }

        # Also try to find version info from common patterns
        if (-not $foundValues['AppVersion']) {
            # Try pattern like "1.2.3" or "v1.2.3" near AppName or version markers
            if ($fileContent -match 'ersion[=:\s]+v?(\d+\.\d+(?:\.\d+)?(?:\.\d+)?)') {
                $foundValues['AppVersion'] = $matches[1]
            }
        }

        if ($foundValues.Count -gt 0) {
            $result.ProductName = $foundValues['AppName']
            $result.ProductVersion = $foundValues['AppVersion']
            $result.Publisher = $foundValues['AppPublisher']

            # AppVerName often contains both name and version
            if (-not $result.ProductName -and $foundValues['AppVerName']) {
                $verName = $foundValues['AppVerName']
                # Try to split "AppName v1.2.3" or "AppName 1.2.3"
                if ($verName -match '^(.+?)\s+v?(\d+\.\d+.*)$') {
                    $result.ProductName = $matches[1]
                    if (-not $result.ProductVersion) {
                        $result.ProductVersion = $matches[2]
                    }
                }
                else {
                    $result.ProductName = $verName
                }
            }

            $result.Success = ($null -ne $result.ProductName -or $null -ne $result.ProductVersion -or $null -ne $result.Publisher)

            Write-Action1Log "Inno Setup metadata extracted" -Level DEBUG -Data $foundValues
        }
    }
    catch {
        Write-Action1Log "Failed to extract Inno Setup metadata" -Level DEBUG -ErrorRecord $_
    }

    return $result
}

function Get-NsisMetadata {
    <#
    .SYNOPSIS
        Extracts metadata from NSIS (Nullsoft Scriptable Install System) installers.

    .DESCRIPTION
        Detects NSIS installers by signature and attempts to extract
        embedded metadata including product name, version, and publisher.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Write-Action1Log "Attempting to extract NSIS metadata from: $Path" -Level DEBUG

    $result = @{
        Success = $false
        ProductName = $null
        ProductVersion = $null
        Publisher = $null
        InstallerType = $null
        Source = "NSIS"
    }

    try {
        # Read the file content
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $fileContent = [System.Text.Encoding]::ASCII.GetString($bytes[0..([Math]::Min(2MB, $bytes.Length - 1))])

        # Check for NSIS signatures
        $isNsis = $false
        $nsisSignatures = @(
            'NullsoftInst',
            'Nullsoft Install System',
            'NSIS Error',
            'nsis.sf.net'
        )

        foreach ($sig in $nsisSignatures) {
            if ($fileContent -match [regex]::Escape($sig)) {
                $isNsis = $true
                $result.InstallerType = "NSIS"
                break
            }
        }

        if (-not $isNsis) {
            Write-Action1Log "File does not appear to be an NSIS installer" -Level DEBUG
            return $result
        }

        Write-Action1Log "NSIS signature detected, extracting metadata..." -Level DEBUG

        # NSIS installers often have strings embedded that we can extract
        # Look for common patterns

        # Try to find Name and Version from NSIS script defines
        # NSIS uses !define statements which may be embedded

        $patterns = @{
            'PRODUCT_NAME' = '(?:PRODUCT_NAME|APP_NAME|NAME)[="\s]+([^\x00\r\n"]+)'
            'PRODUCT_VERSION' = '(?:PRODUCT_VERSION|APP_VERSION|VERSION)[="\s]+v?([0-9][^\x00\r\n"]*)'
            'PRODUCT_PUBLISHER' = '(?:PRODUCT_PUBLISHER|PUBLISHER|COMPANY)[="\s]+([^\x00\r\n"]+)'
        }

        $foundValues = @{}
        foreach ($key in $patterns.Keys) {
            if ($fileContent -match $patterns[$key]) {
                $value = $matches[1].Trim().Trim('"')
                $value = $value -replace '[^\x20-\x7E]', ''
                if ($value.Length -gt 0 -and $value.Length -lt 200) {
                    $foundValues[$key] = $value
                }
            }
        }

        # Also look for branding text which often contains product info
        if ($fileContent -match 'Nullsoft Install System v[\d.]+') {
            # Try to find the installer title near the beginning
            if ($fileContent -match '(?<=\x00)([A-Za-z][A-Za-z0-9\s\-_.]+(?:Setup|Install(?:er)?|v?\d+\.\d+)[A-Za-z0-9\s\-_.]*?)(?=\x00)') {
                $potentialName = $matches[1].Trim()
                if ($potentialName.Length -gt 3 -and $potentialName.Length -lt 100 -and -not $foundValues['PRODUCT_NAME']) {
                    $foundValues['PRODUCT_NAME'] = $potentialName -replace '\s*(Setup|Installer?)$', ''
                }
            }
        }

        if ($foundValues.Count -gt 0) {
            $result.ProductName = $foundValues['PRODUCT_NAME']
            $result.ProductVersion = $foundValues['PRODUCT_VERSION']
            $result.Publisher = $foundValues['PRODUCT_PUBLISHER']
            $result.Success = ($null -ne $result.ProductName -or $null -ne $result.ProductVersion -or $null -ne $result.Publisher)

            Write-Action1Log "NSIS metadata extracted" -Level DEBUG -Data $foundValues
        }
    }
    catch {
        Write-Action1Log "Failed to extract NSIS metadata" -Level DEBUG -ErrorRecord $_
    }

    return $result
}

function Get-FileVersionMetadata {
    <#
    .SYNOPSIS
        Extracts metadata from PE file version information resources.

    .DESCRIPTION
        Uses System.Diagnostics.FileVersionInfo to read the standard Windows
        version resource embedded in PE files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Write-Action1Log "Extracting file version info metadata from: $Path" -Level DEBUG

    $result = @{
        Success = $false
        ProductName = $null
        ProductVersion = $null
        FileVersion = $null
        Publisher = $null
        Description = $null
        Source = "File Version Info"
    }

    try {
        $fileVersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)

        $result.ProductName = if ($fileVersionInfo.ProductName) { $fileVersionInfo.ProductName.Trim() } else { $null }
        $result.ProductVersion = if ($fileVersionInfo.ProductVersion) {
            ($fileVersionInfo.ProductVersion -split '[\s\-]')[0].Trim()
        } else { $null }
        $result.FileVersion = if ($fileVersionInfo.FileVersion) {
            ($fileVersionInfo.FileVersion -split '[\s\-]')[0].Trim()
        } else { $null }
        $result.Publisher = if ($fileVersionInfo.CompanyName) { $fileVersionInfo.CompanyName.Trim() } else { $null }
        $result.Description = if ($fileVersionInfo.FileDescription) { $fileVersionInfo.FileDescription.Trim() } else { $null }

        $result.Success = ($null -ne $result.ProductName -or $null -ne $result.ProductVersion -or $null -ne $result.Publisher)

        Write-Action1Log "File version info metadata extracted" -Level DEBUG -Data @{
            ProductName = $result.ProductName
            ProductVersion = $result.ProductVersion
            FileVersion = $result.FileVersion
            Publisher = $result.Publisher
            Description = $result.Description
        }
    }
    catch {
        Write-Action1Log "Failed to extract file version info metadata" -Level DEBUG -ErrorRecord $_
    }

    return $result
}

function Get-InstallerMetadata {
    <#
    .SYNOPSIS
        Comprehensive metadata extraction from installer files with multiple fallback methods.

    .DESCRIPTION
        Attempts to extract metadata from installers using multiple techniques:
        1. MSI database querying (for .msi files)
        2. PE file version information
        3. Digital signature certificate parsing
        4. Inno Setup script extraction
        5. NSIS installer detection and extraction

        Results are merged with priority given to more reliable sources.

    .PARAMETER Path
        Path to the installer file (.exe or .msi)

    .EXAMPLE
        $metadata = Get-InstallerMetadata -Path "C:\Downloads\setup.exe"
        Write-Host "Product: $($metadata.ProductName) v$($metadata.ProductVersion) by $($metadata.Publisher)"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Installer file not found: $Path"
    }

    $installerFile = Get-Item $Path
    $extension = $installerFile.Extension.ToLower()

    Write-Action1Log "Starting comprehensive metadata extraction for: $($installerFile.Name)" -Level INFO

    # Initialize result with defaults
    $result = @{
        ProductName = $null
        ProductVersion = $null
        Publisher = $null
        Description = $null
        InstallerType = $null
        Sources = @()
        AllMetadata = @{}
    }

    # Collection of all extraction results for debugging/logging
    $extractionResults = @()

    # 1. MSI Database (highest priority for MSI files)
    if ($extension -eq '.msi') {
        Write-Host "  Querying MSI database..." -ForegroundColor Gray
        $msiResult = Get-MsiMetadata -Path $Path
        $extractionResults += $msiResult
        $result.AllMetadata['MSI'] = $msiResult

        if ($msiResult.Success) {
            $result.Sources += "MSI Database"
            if (-not $result.ProductName -and $msiResult.ProductName) { $result.ProductName = $msiResult.ProductName }
            if (-not $result.ProductVersion -and $msiResult.ProductVersion) { $result.ProductVersion = $msiResult.ProductVersion }
            if (-not $result.Publisher -and $msiResult.Manufacturer) { $result.Publisher = $msiResult.Manufacturer }
            if (-not $result.Description -and $msiResult.Description) { $result.Description = $msiResult.Description }
            $result.InstallerType = "MSI"
        }
    }

    # 2. File Version Info (works for both EXE and MSI)
    Write-Host "  Reading file version information..." -ForegroundColor Gray
    $versionResult = Get-FileVersionMetadata -Path $Path
    $extractionResults += $versionResult
    $result.AllMetadata['FileVersion'] = $versionResult

    if ($versionResult.Success) {
        $result.Sources += "File Version Info"
        if (-not $result.ProductName -and $versionResult.ProductName) { $result.ProductName = $versionResult.ProductName }
        if (-not $result.ProductVersion -and $versionResult.ProductVersion) { $result.ProductVersion = $versionResult.ProductVersion }
        if (-not $result.ProductVersion -and $versionResult.FileVersion) { $result.ProductVersion = $versionResult.FileVersion }
        if (-not $result.Publisher -and $versionResult.Publisher) { $result.Publisher = $versionResult.Publisher }
        if (-not $result.Description -and $versionResult.Description) { $result.Description = $versionResult.Description }
    }

    # 3. Digital Signature (good for publisher info)
    Write-Host "  Checking digital signature..." -ForegroundColor Gray
    $sigResult = Get-DigitalSignatureMetadata -Path $Path
    $extractionResults += $sigResult
    $result.AllMetadata['DigitalSignature'] = $sigResult

    if ($sigResult.Success) {
        $result.Sources += "Digital Signature"
        # Only use signature for publisher if we don't have one yet
        if (-not $result.Publisher -and $sigResult.Publisher) { $result.Publisher = $sigResult.Publisher }
    }

    # 4. Inno Setup detection and extraction (for EXE files)
    if ($extension -eq '.exe') {
        Write-Host "  Checking for Inno Setup installer..." -ForegroundColor Gray
        $innoResult = Get-InnoSetupMetadata -Path $Path
        $extractionResults += $innoResult
        $result.AllMetadata['InnoSetup'] = $innoResult

        if ($innoResult.Success) {
            $result.Sources += "Inno Setup"
            $result.InstallerType = "Inno Setup"
            if (-not $result.ProductName -and $innoResult.ProductName) { $result.ProductName = $innoResult.ProductName }
            if (-not $result.ProductVersion -and $innoResult.ProductVersion) { $result.ProductVersion = $innoResult.ProductVersion }
            if (-not $result.Publisher -and $innoResult.Publisher) { $result.Publisher = $innoResult.Publisher }
        }

        # 5. NSIS detection and extraction (for EXE files, if not Inno)
        if (-not $innoResult.Success -or -not $result.InstallerType) {
            Write-Host "  Checking for NSIS installer..." -ForegroundColor Gray
            $nsisResult = Get-NsisMetadata -Path $Path
            $extractionResults += $nsisResult
            $result.AllMetadata['NSIS'] = $nsisResult

            if ($nsisResult.Success) {
                $result.Sources += "NSIS"
                if (-not $result.InstallerType) { $result.InstallerType = "NSIS" }
                if (-not $result.ProductName -and $nsisResult.ProductName) { $result.ProductName = $nsisResult.ProductName }
                if (-not $result.ProductVersion -and $nsisResult.ProductVersion) { $result.ProductVersion = $nsisResult.ProductVersion }
                if (-not $result.Publisher -and $nsisResult.Publisher) { $result.Publisher = $nsisResult.Publisher }
            }
        }
    }

    # Set default installer type if not detected
    if (-not $result.InstallerType) {
        $result.InstallerType = switch ($extension) {
            '.msi' { 'MSI' }
            '.exe' { 'EXE' }
            default { 'Unknown' }
        }
    }

    # Apply final fallbacks
    if (-not $result.ProductName) {
        $result.ProductName = [System.IO.Path]::GetFileNameWithoutExtension($installerFile.Name)
        $result.Sources += "Filename (fallback)"
    }
    if (-not $result.ProductVersion) {
        $result.ProductVersion = "1.0.0"
        $result.Sources += "Default version (fallback)"
    }
    if (-not $result.Publisher) {
        $result.Publisher = "Unknown"
    }

    Write-Action1Log "Metadata extraction complete" -Level INFO -Data @{
        ProductName = $result.ProductName
        ProductVersion = $result.ProductVersion
        Publisher = $result.Publisher
        InstallerType = $result.InstallerType
        Sources = $result.Sources -join ', '
    }

    return $result
}

#endregion
#region Public Functions

function Set-Action1ApiCredentials {
    <#
    .SYNOPSIS
        Sets the Action1 API credentials for use in the module.

    .DESCRIPTION
        Configures the Client ID, Client Secret, and Region for authenticating with Action1 API.
        Credentials are stored in memory for the current session only.
        If Region is not specified, prompts the user to select one.

    .PARAMETER ClientId
        The Action1 API Client ID.

    .PARAMETER ClientSecret
        The Action1 API Client Secret.

    .PARAMETER Region
        The Action1 region (NorthAmerica, Europe, Australia).
        If not specified, prompts the user to select.

    .PARAMETER SaveToProfile
        If specified, saves credentials to a secure local file for persistence.

    .EXAMPLE
        Set-Action1ApiCredentials -ClientId "your-client-id" -ClientSecret "your-secret" -Region "Australia"

    .EXAMPLE
        Set-Action1ApiCredentials -ClientId "your-client-id" -ClientSecret "your-secret"
        # Will prompt for region selection
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [string]$ClientSecret,

        [Parameter()]
        [ValidateSet('NorthAmerica', 'Europe', 'Australia')]
        [string]$Region,

        [Parameter()]
        [switch]$SaveToProfile
    )

    Write-Action1Log "Configuring Action1 API credentials" -Level INFO
    Write-Action1Log "Client ID length: $($ClientId.Length) characters" -Level DEBUG

    # Prompt for region if not provided
    if (-not $Region) {
        Write-Host "`nSelect Action1 Region:" -ForegroundColor Cyan
        Write-Host "  [0] NorthAmerica (app.action1.com) (default)"
        Write-Host "  [1] Europe (app.eu.action1.com)"
        Write-Host "  [2] Australia (app.au.action1.com)"

        $selection = Read-Host "`nEnter selection (0-2)"
        $Region = switch ($selection) {
            '0' { 'NorthAmerica' }
            '' { 'NorthAmerica' }
            '1' { 'Europe' }
            '2' { 'Australia' }
            default {
                Write-Warning "Invalid selection. Defaulting to NorthAmerica."
                'NorthAmerica'
            }
        }
        Write-Host "Selected: $Region" -ForegroundColor Green
    }

    Write-Action1Log "Selected region: $Region" -Level INFO

    $script:Action1ClientId = $ClientId
    $script:Action1ClientSecret = $ClientSecret
    $script:Action1Region = $Region
    $script:Action1BaseUri = $script:Action1RegionUrls[$Region]

    Write-Action1Log "API Base URI set to: $($script:Action1BaseUri)" -Level DEBUG
    Write-Action1Log "Credentials set in memory for current session" -Level INFO

    if ($SaveToProfile) {
        Write-Action1Log "Saving credentials to profile" -Level INFO

        Write-Action1Log "Profile path: $script:Action1ConfigDir" -Level DEBUG

        if (-not (Test-Path $script:Action1ConfigDir)) {
            Write-Action1Log "Creating profile directory" -Level DEBUG
            New-Item -Path $script:Action1ConfigDir -ItemType Directory -Force | Out-Null
        }

        $credFile = Join-Path $script:Action1ConfigDir "credentials.json"

        try {
            @{
                ClientId = $ClientId
                ClientSecret = $ClientSecret
                Region = $Region
            } | ConvertTo-Json | Set-Content $credFile -Force

            Write-Action1Log "Credentials saved to: $credFile" -Level INFO
            Write-Host "Credentials saved to: $credFile" -ForegroundColor Green
        }
        catch {
            Write-Action1Log "Failed to save credentials to file" -Level ERROR -ErrorRecord $_
            throw
        }
    }

    Write-Host "`nAction1 API credentials configured successfully." -ForegroundColor Green
    Write-Host "Region: $Region" -ForegroundColor Cyan
    Write-Host "API Endpoint: $($script:Action1BaseUri)" -ForegroundColor Cyan
}

function Get-Action1ApiCredentials {
    <#
    .SYNOPSIS
        Retrieves the current Action1 API credentials and validates permissions.

    .DESCRIPTION
        Returns information about the currently configured API credentials including
        region, endpoint, and token status. Optionally validates the credentials
        by making an API call to check accessible organizations and permissions.

    .PARAMETER TestConnection
        If specified, makes an API call to validate credentials and check permissions.

    .PARAMETER ShowSecret
        If specified, includes the client secret in the output (masked by default).

    .EXAMPLE
        Get-Action1ApiCredentials
        # Returns current credential info without API validation

    .EXAMPLE
        Get-Action1ApiCredentials -TestConnection
        # Returns credential info and validates by checking accessible organizations

    .EXAMPLE
        Get-Action1ApiCredentials -ShowSecret
        # Includes the client secret in the output
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$TestConnection,

        [Parameter()]
        [switch]$ShowSecret
    )

    Write-Action1Log "Retrieving Action1 API credentials" -Level INFO

    # Check if credentials are configured
    $isConfigured = $null -ne $script:Action1ClientId -and $null -ne $script:Action1ClientSecret

    if (-not $isConfigured) {
        Write-Action1Log "No credentials configured" -Level WARN
        Write-Host "No Action1 API credentials configured." -ForegroundColor Yellow
        Write-Host "Use Set-Action1ApiCredentials to configure." -ForegroundColor Cyan
        return [PSCustomObject]@{
            Configured     = $false
            ClientId       = $null
            Region         = $null
            Endpoint       = $null
            TokenStatus    = 'Not Available'
            Organizations  = @()
            Permissions    = @()
        }
    }

    # Build credential info object
    $credInfo = [PSCustomObject]@{
        Configured     = $true
        ClientId       = $script:Action1ClientId
        ClientSecret   = if ($ShowSecret) { $script:Action1ClientSecret } else { '********' }
        Region         = $script:Action1Region
        Endpoint       = $script:Action1BaseUri
        TokenStatus    = 'Unknown'
        TokenExpiry    = $null
        Organizations  = @()
        Permissions    = @()
    }

    # Check token status
    if ($script:Action1AccessToken) {
        if ($script:Action1TokenExpiry -and (Get-Date) -lt $script:Action1TokenExpiry) {
            $credInfo.TokenStatus = 'Valid'
            $credInfo.TokenExpiry = $script:Action1TokenExpiry
        }
        else {
            $credInfo.TokenStatus = 'Expired'
            $credInfo.TokenExpiry = $script:Action1TokenExpiry
        }
    }
    else {
        $credInfo.TokenStatus = 'Not Acquired'
    }

    Write-Action1Log "Credentials configured for region: $($script:Action1Region)" -Level DEBUG

    # If TestConnection requested, validate by calling API
    if ($TestConnection) {
        Write-Action1Log "Testing connection and checking permissions..." -Level INFO
        Write-Host "`nValidating credentials..." -ForegroundColor Cyan

        try {
            # Get organizations to validate credentials and check access
            $orgsResponse = Invoke-Action1ApiRequest -Endpoint "organizations" -Method GET
            $orgs = if ($orgsResponse.items) { @($orgsResponse.items) } else { @($orgsResponse) }

            $credInfo.Organizations = $orgs | ForEach-Object {
                [PSCustomObject]@{
                    Id   = $_.id
                    Name = $_.name
                    Type = $_.type
                }
            }

            # Update token status after successful call
            $credInfo.TokenStatus = 'Valid'
            $credInfo.TokenExpiry = $script:Action1TokenExpiry

            # Determine permissions based on accessible resources
            $permissions = @()

            # Check organizations access
            if ($orgs.Count -gt 0) {
                $permissions += 'Organizations:Read'
            }

            # Try to check software repository access (use first org or 'all')
            $testOrgId = if ($orgs.Count -gt 0) { $orgs[0].id } else { 'all' }
            try {
                $null = Invoke-Action1ApiRequest `
                    -Endpoint "software-repository/$testOrgId`?limit=1" `
                    -Method GET
                $permissions += 'SoftwareRepository:Read'
                Write-Action1Log "Software repository access confirmed" -Level DEBUG
            }
            catch {
                Write-Action1Log "No software repository read access" -Level DEBUG
            }

            # Try to check automations access
            try {
                $null = Invoke-Action1ApiRequest `
                    -Endpoint "automations/$testOrgId`?limit=1" `
                    -Method GET
                $permissions += 'Automations:Read'
                Write-Action1Log "Automations access confirmed" -Level DEBUG
            }
            catch {
                Write-Action1Log "No automations read access" -Level DEBUG
            }

            # Try to check endpoint groups access
            try {
                $null = Invoke-Action1ApiRequest `
                    -Endpoint "endpointgroups/$testOrgId`?limit=1" `
                    -Method GET
                $permissions += 'EndpointGroups:Read'
                Write-Action1Log "Endpoint groups access confirmed" -Level DEBUG
            }
            catch {
                Write-Action1Log "No endpoint groups read access" -Level DEBUG
            }

            $credInfo.Permissions = $permissions

            Write-Host "`n✓ Credentials validated successfully" -ForegroundColor Green
            Write-Host "`nAccessible Organizations:" -ForegroundColor Cyan
            foreach ($org in $credInfo.Organizations) {
                Write-Host "  - $($org.Name) ($($org.Id))" -ForegroundColor White
            }

            Write-Host "`nDetected Permissions:" -ForegroundColor Cyan
            foreach ($perm in $permissions) {
                Write-Host "  ✓ $perm" -ForegroundColor Green
            }
        }
        catch {
            Write-Action1Log "Failed to validate credentials" -Level ERROR -ErrorRecord $_
            Write-Host "`n✗ Failed to validate credentials: $($_.Exception.Message)" -ForegroundColor Red
            $credInfo.TokenStatus = 'Invalid'
        }
    }
    else {
        # Display basic info without API call
        Write-Host "`nAction1 API Credentials:" -ForegroundColor Cyan
        Write-Host "  Client ID:  $($credInfo.ClientId)" -ForegroundColor White
        Write-Host "  Region:     $($credInfo.Region)" -ForegroundColor White
        Write-Host "  Endpoint:   $($credInfo.Endpoint)" -ForegroundColor White
        Write-Host "  Token:      $($credInfo.TokenStatus)" -ForegroundColor $(if ($credInfo.TokenStatus -eq 'Valid') { 'Green' } elseif ($credInfo.TokenStatus -eq 'Expired') { 'Yellow' } else { 'Gray' })
        if ($credInfo.TokenExpiry) {
            Write-Host "  Expires:    $($credInfo.TokenExpiry)" -ForegroundColor Gray
        }
        Write-Host "`nUse -TestConnection to validate credentials and check permissions." -ForegroundColor DarkGray
    }

    return $credInfo
}

# TODO: implement function to silently run in Get-Action1ApiCredentials and  
function Test-Action1Connection {
    <#
    .SYNOPSIS
        Tests the connection to Action1 API.
    
    .DESCRIPTION
        Validates that the API credentials are correct and the API is accessible.
    
    .EXAMPLE
        Test-Action1Connection
    #>
    [CmdletBinding()]
    param()
    
    Write-Action1Log "Testing Action1 API connection" -Level INFO
    
    try {
        Write-Action1Log "Attempting to query organizations endpoint" -Level DEBUG
        # Try to list organizations (lightweight API call)
        $response = Invoke-Action1ApiRequest -Endpoint "organizations" -Method GET
        
        Write-Action1Log "API connection test successful" -Level INFO
        Write-Action1Log "Organizations retrieved" -Level TRACE -Data $response
        
        Write-Host "✓ Successfully connected to Action1 API" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Action1Log "API connection test failed" -Level ERROR -ErrorRecord $_
        Write-Host "✗ Failed to connect to Action1 API" -ForegroundColor Red
        return $false
    }
}

# TODO: implement function in Deploy-Action1AppRepo
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
# TODO: Prompt for configuration of additional actions before displaying options
function New-Action1AppPackage {
    <#
    .SYNOPSIS
        Creates a new Action1 application package with support for multiple architectures.

    .DESCRIPTION
        Prompts for application metadata and creates the package folder structure
        in /vendor/app/version/ format. Supports adding installers for multiple
        architectures (x86, x64, arm64).

    .PARAMETER BasePath
        Base path where the package folder structure will be created.
        Defaults to current directory.

    .PARAMETER Publisher
        Publisher/vendor name. If not provided, will prompt.

    .PARAMETER AppName
        Application name. If not provided, will prompt.

    .PARAMETER Version
        Application version. If not provided, will prompt.

    .PARAMETER Description
        Application description. Optional.

    .EXAMPLE
        New-Action1AppPackage
        # Interactive mode - prompts for all information

    .EXAMPLE
        New-Action1AppPackage -Publisher "Microsoft" -AppName "PowerShell" -Version "7.4.0"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$BasePath = (Get-Location).Path,

        [Parameter()]
        [string]$Publisher,

        [Parameter()]
        [string]$AppName,

        [Parameter()]
        [string]$Version,

        [Parameter()]
        [string]$Description
    )

    Write-Host "`n=== Action1 Application Packager ===" -ForegroundColor Cyan
    Write-Action1Log "Creating new application package" -Level INFO

    # Get existing folders for auto-completion
    $existingVendors = @(Get-ExistingVendors -BasePath $BasePath)

    # Prompt for application information
    Write-Host "`n--- Application Information ---" -ForegroundColor Cyan

    if (-not $Publisher) {
        $Publisher = Read-HostWithCompletion `
            -Prompt "Vendor/Publisher" `
            -Suggestions $existingVendors `
            -Required
    }

    $sanitizedVendorForLookup = $Publisher -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
    $existingApps = @(Get-ExistingApps -BasePath $BasePath -Vendor $sanitizedVendorForLookup)

    if (-not $AppName) {
        $AppName = Read-HostWithCompletion `
            -Prompt "Application Name" `
            -Suggestions $existingApps `
            -Required
    }

    $sanitizedAppForLookup = $AppName -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
    $existingVersions = @(Get-ExistingVersions -BasePath $BasePath -Vendor $sanitizedVendorForLookup -AppName $sanitizedAppForLookup)

    if (-not $Version) {
        $Version = Read-HostWithCompletion `
            -Prompt "Version" `
            -Suggestions $existingVersions `
            -Default "1.0.0"
    }

    if (-not $Description) {
        Write-Host "Description (optional): " -NoNewline
        $Description = Read-Host
    }

    # Sanitize names for folder creation (remove punctuation, replace spaces with underscores)
    $sanitizedPublisher = $Publisher -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
    $sanitizedAppName = $AppName -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
    $sanitizedVersion = $Version -replace '[\\/:*?"<>|]', '_'

    # Create folder structure: /vendor/app/version/
    $packagePath = Join-Path $BasePath $sanitizedPublisher $sanitizedAppName $sanitizedVersion

    Write-Host "`n--- Creating Package Structure ---" -ForegroundColor Cyan
    Write-Host "Package path: $packagePath"
    Write-Action1Log "Creating package folder structure: $packagePath" -Level INFO

    # Create directories including architecture-specific installer folders
    $directories = @(
        $packagePath,
        (Join-Path $packagePath "installers"),
        (Join-Path $packagePath "installers" "x86"),
        (Join-Path $packagePath "installers" "x64"),
        (Join-Path $packagePath "installers" "arm64"),
        (Join-Path $packagePath "scripts"),
        (Join-Path $packagePath "documentation")
    )

    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            Write-Action1Log "Creating directory: $dir" -Level DEBUG
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
    Write-Host "  Created folder structure" -ForegroundColor Green

    # Prompt for installers
    Write-Host "`n--- Add Installers ---" -ForegroundColor Cyan

    $installers = @{
        x86 = $null
        x64 = $null
        arm64 = $null
    }
    $installerType = "exe"
    $installSwitches = ""
    $uninstallSwitches = ""

    $architectures = @('x64', 'x86', 'arm64')

    foreach ($arch in $architectures) {
        Write-Host "`n$arch installer" -ForegroundColor Yellow
        $installerPath = Read-HostWithFileCompletion `
            -Prompt "Path (Enter to skip)" `
            -Filter "*.exe,*.msi" `
            -BasePath $BasePath

        if ($installerPath -and (Test-Path $installerPath -PathType Leaf)) {
            $installerFile = Get-Item $installerPath
            $extension = $installerFile.Extension.ToLower()

            if ($extension -notin @('.exe', '.msi')) {
                Write-Host "  Skipped: Unsupported type ($extension)" -ForegroundColor Yellow
                continue
            }

            # Copy installer to architecture folder
            $destPath = Join-Path $packagePath "installers" $arch $installerFile.Name
            Copy-Item -Path $installerFile.FullName -Destination $destPath -Force
            Write-Host "  Added: $($installerFile.Name)" -ForegroundColor Green

            $installers[$arch] = @{
                FileName = $installerFile.Name
                Path = $destPath
                Size = $installerFile.Length
                Type = if ($extension -eq '.msi') { 'msi' } else { 'exe' }
            }

            # Use first installer's type as default
            if (-not $installerType -or $installerType -eq 'exe') {
                $installerType = $installers[$arch].Type
            }
        }
        elseif ($installerPath) {
            Write-Host "  File not found: $installerPath" -ForegroundColor Red
        }
    }

    # Check if at least one installer was added
    $hasInstallers = ($installers.Values | Where-Object { $_ -ne $null }).Count -gt 0

    if (-not $hasInstallers) {
        Write-Host "`nNo installers added. You can add them later to:" -ForegroundColor Yellow
        Write-Host "  $packagePath\installers\<arch>\" -ForegroundColor Cyan
    }
    else {
        # Prompt for install switches
        Write-Host "`n--- Silent Install Arguments ---" -ForegroundColor Cyan

        if ($installerType -eq 'msi') {
            Write-Host "Default MSI switches: $script:DefaultMsiSwitches (automatically added by Action1)"
            Write-Host "Additional install switches (press Enter for none): " -NoNewline
            $installSwitches = Read-Host
        }
        else {
            Write-Host "Common silent switches:"
            Write-Host "  /S              - NSIS"
            Write-Host "  /verysilent     - Inno Setup"
            Write-Host "  /quiet          - Many installers"
            Write-Host "Install switches [/S]: " -NoNewline
            $installSwitches = Read-Host
            if (-not $installSwitches) { $installSwitches = "/S" }
        }

        Write-Host "Uninstall switches [same as install]: " -NoNewline
        $uninstallSwitches = Read-Host
        if (-not $uninstallSwitches) { $uninstallSwitches = $installSwitches }
    }

    # Prompt for version/release information
    Write-Host "`n--- Version Information ---" -ForegroundColor Cyan

    # Release date
    $defaultReleaseDate = Get-Date -Format "yyyy-MM-dd"
    Write-Host "Release Date (yyyy-MM-dd) [$defaultReleaseDate]: " -NoNewline
    $releaseDate = Read-Host
    if (-not $releaseDate) { $releaseDate = $defaultReleaseDate }
    # Validate date format
    try {
        [datetime]::ParseExact($releaseDate, "yyyy-MM-dd", $null) | Out-Null
    }
    catch {
        Write-Host "  Invalid date format, using today's date" -ForegroundColor Yellow
        $releaseDate = $defaultReleaseDate
    }

    # Update Type
    $updateTypes = @('Regular Updates', 'Security Updates', 'Critical Updates')
    Write-Host "`nUpdate Type:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $updateTypes.Count; $i++) {
        $marker = if ($i -eq 0) { " (default)" } else { "" }
        Write-Host "  [$i] $($updateTypes[$i])$marker"
    }
    $updateTypeSelection = Read-Host "`nEnter selection (0-$($updateTypes.Count - 1))"
    if (-not $updateTypeSelection) { $updateTypeSelection = "0" }
    $updateType = $updateTypes[[int]$updateTypeSelection]
    Write-Host "Selected: $updateType" -ForegroundColor Green

    # Security Severity (only if Security Updates)
    $securitySeverity = "Unspecified"
    if ($updateType -eq 'Security Updates') {
        $severities = @('Unspecified', 'Low', 'Medium', 'High', 'Critical')
        Write-Host "`nSecurity Severity:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $severities.Count; $i++) {
            $marker = if ($i -eq 0) { " (default)" } else { "" }
            Write-Host "  [$i] $($severities[$i])$marker"
        }
        $severitySelection = Read-Host "`nEnter selection (0-$($severities.Count - 1))"
        if (-not $severitySelection) { $severitySelection = "0" }
        $securitySeverity = $severities[[int]$severitySelection]
        Write-Host "Selected: $securitySeverity" -ForegroundColor Green
    }

    # CVEs (optional)
    Write-Host "`nCVEs (comma-separated, optional): " -NoNewline
    $cvesInput = Read-Host
    $cves = @()
    if ($cvesInput) {
        $cves = $cvesInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    # EULA (optional)
    Write-Host "EULA URL or text (optional): " -NoNewline
    $eula = Read-Host

    # Additional Actions (optional)
    Write-Host "`nAdditional Actions (optional):" -ForegroundColor Cyan
    $actionOptions = @(
        @{ Name = 'Deploy Software'; Value = 'deploy_software' }
        @{ Name = 'Deploy Updates'; Value = 'deploy_updates' }
        @{ Name = 'Reboot'; Value = 'reboot' }
        @{ Name = 'Run Script'; Value = 'run_script' }
        @{ Name = 'Uninstall Software'; Value = 'uninstall_software' }
        @{ Name = 'Update Ring'; Value = 'update_ring' }
    )
    for ($i = 0; $i -lt $actionOptions.Count; $i++) {
        Write-Host "  [$i] $($actionOptions[$i].Name)"
    }
    $actionsInput = Read-Host "`nEnter selection(s) (0-$($actionOptions.Count - 1), comma-separated, Enter to skip)"

    $additionalActions = @()
    if ($actionsInput) {
        $selectedIndices = $actionsInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
        foreach ($idx in $selectedIndices) {
            $index = [int]$idx
            if ($index -ge 0 -and $index -lt $actionOptions.Count) {
                $action = @{
                    Type = $actionOptions[$index].Value
                    Name = $actionOptions[$index].Name
                }

                # For Run Script, we'll add script selection later
                if ($action.Type -eq 'run_script') {
                    Write-Host "  Script selection will be configured during deployment" -ForegroundColor DarkGray
                    $action.ScriptId = ""
                    $action.ScriptName = ""
                }

                $additionalActions += $action
            }
        }
        if ($additionalActions.Count -gt 0) {
            Write-Host "Selected: $($additionalActions.Name -join ', ')" -ForegroundColor Green
        }
    }

    # Build installers array for manifest
    $installersArray = @()
    foreach ($arch in $architectures) {
        if ($installers[$arch]) {
            $installersArray += @{
                Architecture = $arch
                FileName = $installers[$arch].FileName
                Type = $installers[$arch].Type
            }
        }
    }

    # Generate app name match patterns for Action1 detection
    $appNamePatterns = Get-AppNameMatchPatterns -AppName $AppName

    # Create manifest
    $manifest = [PSCustomObject]@{
        AppName = $AppName
        Publisher = $Publisher
        Description = if ($Description) { $Description } else { "" }
        Version = $Version
        ReleaseDate = $releaseDate
        CreatedDate = Get-Date -Format "yyyy-MM-dd"
        LastModified = Get-Date -Format "yyyy-MM-dd"
        InstallerType = $installerType
        Installers = $installersArray
        InstallSwitches = $installSwitches
        UninstallSwitches = $uninstallSwitches
        AppNameMatch = @{
            Specific = $appNamePatterns.Specific
            Broad = $appNamePatterns.Broad
        }
        UpdateInfo = @{
            UpdateType = $updateType
            SecuritySeverity = $securitySeverity
            CVEs = $cves
            Eula = $eula
        }
        AdditionalActions = $additionalActions
        DetectionMethod = @{
            Type = "registry"
            Path = ""
            Value = ""
        }
        Requirements = @{
            OSVersion = ""
            MinDiskSpaceMB = 0
            MinMemoryMB = 0
        }
        Action1Config = @{
            OrganizationId = ""
            PackageId = ""
            PolicyId = ""
            DeploymentGroup = ""
        }
        Metadata = @{
            Tags = @()
            Notes = ""
        }
    }

    # Save manifest
    $manifestPath = Join-Path $packagePath "manifest.json"
    Write-Action1Log "Creating manifest file: $manifestPath" -Level INFO
    Write-ManifestFile -Manifest $manifest -Path $manifestPath

    # Create README
    $installersList = if ($installersArray.Count -gt 0) {
        ($installersArray | ForEach-Object { "- **$($_.Architecture)**: $($_.FileName)" }) -join "`n"
    } else {
        "- No installers added yet"
    }

    $msiNote = if ($installerType -eq 'msi') { "**Note:** Action1 automatically adds: $script:DefaultMsiSwitches" } else { "" }
    $switchesDisplay = if ($installSwitches) { $installSwitches } else { '(default)' }

    $readmeContent = @(
        "# $AppName - Action1 Deployment Package",
        "",
        "## Overview",
        "$Description",
        "",
        "**Publisher:** $Publisher",
        "**Version:** $Version",
        "**Created:** $(Get-Date -Format 'yyyy-MM-dd')",
        "",
        "## Structure",
        "- **installers/** - Architecture-specific installer files",
        "  - **x86/** - 32-bit installers",
        "  - **x64/** - 64-bit installers",
        "  - **arm64/** - ARM64 installers",
        "- **scripts/** - Pre/post installation scripts",
        "- **documentation/** - Additional documentation",
        "- **manifest.json** - Application deployment configuration",
        "",
        "## Installers",
        "$installersList",
        "",
        "## Installation",
        "**Installer Type:** $installerType",
        "**Install Switches:** $switchesDisplay",
        "$msiNote",
        "",
        "## Usage",
        '```powershell',
        "# Deploy to Action1",
        "Deploy-Action1AppPackage -ManifestPath `"$manifestPath`"",
        "",
        "# Deploy update to existing application",
        "Deploy-Action1AppUpdate -ManifestPath `"$manifestPath`"",
        '```'
    ) -join "`n"

    $readmePath = Join-Path $packagePath "README.md"
    Set-Content -Path $readmePath -Value $readmeContent -Force
    Write-Action1Log "Created README file: $readmePath" -Level DEBUG

    # Display summary
    Write-Host "`n=== Package Summary ===" -ForegroundColor Green
    Write-Host "  Vendor:   $Publisher" -ForegroundColor White
    Write-Host "  App:      $AppName" -ForegroundColor White
    Write-Host "  Version:  $Version" -ForegroundColor White
    Write-Host "  Location: $packagePath" -ForegroundColor Cyan

    if ($installersArray.Count -gt 0) {
        Write-Host "`n  Installers:" -ForegroundColor White
        foreach ($inst in $installersArray) {
            Write-Host "    $($inst.Architecture): $($inst.FileName)" -ForegroundColor Gray
        }
    }

    Write-Host "`n✓ Package created successfully!" -ForegroundColor Green
    Write-Host "  Manifest: $manifestPath" -ForegroundColor Cyan

    Write-Action1Log "Package created successfully at: $packagePath" -Level INFO

    return [PSCustomObject]@{
        Success = $true
        PackagePath = $packagePath
        ManifestPath = $manifestPath
        AppName = $AppName
        Version = $Version
        Publisher = $Publisher
        InstallerType = $installerType
        Installers = $installersArray
        Manifest = $manifest
    }
}
# FIXME: Display name (broad) not being set correctly at all
# FIXME: CVE not being set correctly at all
function Deploy-Action1AppPackage {
    <#
    .SYNOPSIS
        Deploys an application to Action1 Software Repository.

    .DESCRIPTION
        Deploys an application using the correct Action1 Software Repository API flow:
        1. Prompts for organization (or uses manifest/parameter value)
        2. Finds matching repository or creates a new one
        3. Creates a new version entry
        4. Uploads installer file(s) using resumable upload protocol

    .PARAMETER ManifestPath
        Path to the manifest.json file.

    .PARAMETER OrganizationId
        Action1 organization ID. If not specified, uses value from manifest or prompts.

    .PARAMETER DryRun
        Shows what would be deployed without actually deploying.

    .EXAMPLE
        Deploy-Action1AppPackage -ManifestPath ".\PowerShell\manifest.json"

    .EXAMPLE
        Deploy-Action1AppPackage -ManifestPath ".\7-Zip\manifest.json" -OrganizationId "all"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [switch]$DryRun
    )

    Write-Host "`n=== Action1 Software Repository Deployment ===" -ForegroundColor Cyan

    # Load manifest
    $manifest = Read-ManifestFile -Path $ManifestPath
    $repoPath = Split-Path $ManifestPath -Parent

    # Handle multiple installers from manifest
    $installers = @()
    if ($manifest.Installers -and $manifest.Installers.Count -gt 0) {
        foreach ($inst in $manifest.Installers) {
            $archFolder = switch ($inst.Architecture) {
                'x64' { 'x64' }
                'x86' { 'x86' }
                'arm64' { 'arm64' }
                default { '' }
            }
            $installerPath = if ($archFolder) {
                Join-Path $repoPath "installers" $archFolder $inst.FileName
            } else {
                Join-Path $repoPath "installers" $inst.FileName
            }

            if (Test-Path $installerPath) {
                $platform = switch ($inst.Architecture) {
                    'x64' { 'Windows_64' }
                    'x86' { 'Windows_32' }
                    'arm64' { 'Windows_ARM64' }
                    default { 'Windows_64' }
                }
                $installers += @{
                    Path = $installerPath
                    FileName = $inst.FileName
                    Platform = $platform
                    Type = $inst.Type
                }
            } else {
                Write-Action1Log "Installer not found: $installerPath" -Level WARN
            }
        }
    }

    # Fallback to legacy InstallerFileName if no installers found
    if ($installers.Count -eq 0 -and $manifest.InstallerFileName) {
        $legacyPath = Join-Path $repoPath "installers" $manifest.InstallerFileName
        if (Test-Path $legacyPath) {
            $installers += @{
                Path = $legacyPath
                FileName = $manifest.InstallerFileName
                Platform = 'Windows_64'
                Type = $manifest.InstallerType
            }
        }
    }

    if ($installers.Count -eq 0) {
        throw "No installer files found in manifest or installers directory"
    }

    Write-Action1Log "Found $($installers.Count) installer(s) to upload" -Level INFO

    # Step 1: Get organization ID
    if (-not $OrganizationId) {
        if ($manifest.Action1Config.OrganizationId) {
            $OrganizationId = $manifest.Action1Config.OrganizationId
            Write-Host "Using organization from manifest: $OrganizationId" -ForegroundColor Green
        } else {
            $selectedOrg = Select-Action1Organization -IncludeAll $true
            $OrganizationId = $selectedOrg.Id

            # Save to manifest for future use
            $manifest.Action1Config.OrganizationId = $OrganizationId
            Write-ManifestFile -Manifest $manifest -Path $ManifestPath
        }
    }

    # Check for -WhatIf or -DryRun
    $isWhatIf = $WhatIfPreference -or $DryRun

    if ($isWhatIf) {
        Write-Host "`n=== Deployment Preview (WhatIf/DryRun) ===" -ForegroundColor Yellow
        Write-Host "Would deploy the following:"
        Write-Host "  App Name: $($manifest.AppName)"
        Write-Host "  Publisher: $($manifest.Publisher)"
        Write-Host "  Version: $($manifest.Version)"
        Write-Host "  Organization: $OrganizationId"
        Write-Host "  Installers:"
        foreach ($inst in $installers) {
            Write-Host "    - $($inst.FileName) ($($inst.Platform))"
        }
        return @{
            Success = $true
            DryRun = $true
            AppName = $manifest.AppName
            Version = $manifest.Version
        }
    }

    Write-Host "`nPreparing deployment..." -ForegroundColor Yellow

    try {
        # Step 2: Select or create software repository
        Write-Host "`nStep 1: Select software repository..." -ForegroundColor Cyan

        $repoSelection = Select-Action1SoftwareRepository `
            -OrganizationId $OrganizationId `
            -DefaultName $manifest.AppName `
            -DefaultVendor $manifest.Publisher `
            -DefaultPlatform 'Windows'

        $repositoryId = $repoSelection.Id
        $isNewRepo = $repoSelection.IsNew

        Write-Host "Repository ID: $repositoryId" -ForegroundColor Green

        # Step 3: Create version
        Write-Host "`nStep 2: Creating version $($manifest.Version)..." -ForegroundColor Cyan

        # Use first installer for the version creation
        $primaryInstaller = $installers[0]

        # Use AppNameMatch.Specific from manifest if available, otherwise generate from AppName
        $appNameMatch = if ($manifest.AppNameMatch -and $manifest.AppNameMatch.Specific) {
            $manifest.AppNameMatch.Specific
        } else {
            $patterns = Get-AppNameMatchPatterns -AppName $manifest.AppName
            $patterns.Specific
        }

        # Get update info from manifest if available
        $releaseDate = if ($manifest.ReleaseDate) { $manifest.ReleaseDate } else { Get-Date -Format 'yyyy-MM-dd' }
        $updateType = if ($manifest.UpdateInfo -and $manifest.UpdateInfo.UpdateType) { $manifest.UpdateInfo.UpdateType } else { 'Regular Updates' }
        $securitySeverity = if ($manifest.UpdateInfo -and $manifest.UpdateInfo.SecuritySeverity) { $manifest.UpdateInfo.SecuritySeverity } else { 'Unspecified' }

        # Build hashtable of all platform files
        $allPlatformFiles = @{}
        foreach ($inst in $installers) {
            $allPlatformFiles[$inst.Platform] = $inst.FileName
        }

        $versionResponse = New-Action1RepositoryVersion `
            -OrganizationId $OrganizationId `
            -RepositoryId $repositoryId `
            -Version $manifest.Version `
            -AppNameMatch $appNameMatch `
            -FileName $primaryInstaller.FileName `
            -Platform $primaryInstaller.Platform `
            -InstallType $manifest.InstallerType `
            -ReleaseDate $releaseDate `
            -UpdateType $updateType `
            -SecuritySeverity $securitySeverity `
            -AllPlatformFiles $allPlatformFiles

        $versionId = $versionResponse.id
        Write-Host "Version created with ID: $versionId" -ForegroundColor Green

        # Step 4: Upload installer file(s)
        Write-Host "`nStep 3: Uploading installer file(s)..." -ForegroundColor Cyan

        if ($installers.Count -gt 1) {
            # Use parallel uploads for multiple architectures
            $uploads = $installers | ForEach-Object {
                @{
                    FilePath = $_.Path
                    Platform = $_.Platform
                }
            }

            $uploadResults = Invoke-Action1MultiFileUpload `
                -Uploads $uploads `
                -OrganizationId $OrganizationId `
                -PackageId $repositoryId `
                -VersionId $versionId `
                -ChunkSizeMB 24

            $failedUploads = $uploadResults | Where-Object { -not $_.Success }
            if ($failedUploads) {
                throw "One or more uploads failed: $(($failedUploads | ForEach-Object { "$($_.Platform): $($_.Error)" }) -join '; ')"
            }
        }
        else {
            # Single file upload
            foreach ($installer in $installers) {
                $null = Invoke-Action1SoftwareRepoUpload `
                    -FilePath $installer.Path `
                    -OrganizationId $OrganizationId `
                    -PackageId $repositoryId `
                    -VersionId $versionId `
                    -Platform $installer.Platform `
                    -ChunkSizeMB 24

                Write-Host "✓ Upload complete: $($installer.FileName)" -ForegroundColor Green
            }
        }

        # Update manifest with IDs
        $manifest.Action1Config.PackageId = $repositoryId
        Write-ManifestFile -Manifest $manifest -Path $ManifestPath

        Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
        Write-Host "Application: $($manifest.AppName) v$($manifest.Version)"
        Write-Host "Organization: $OrganizationId"
        Write-Host "Repository ID: $repositoryId"
        Write-Host "Version ID: $versionId"
        Write-Host "Status: Ready for deployment"

        return @{
            Success = $true
            OrganizationId = $OrganizationId
            RepositoryId = $repositoryId
            VersionId = $versionId
            AppName = $manifest.AppName
            Version = $manifest.Version
        }
    }
    catch {
        Write-Error "Deployment failed: $($_.Exception.Message)"
        Write-Action1Log "Deployment failed" -Level ERROR -ErrorRecord $_
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

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

# TODO: Test function
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

function Get-Action1AppPackage {
    <#
    .SYNOPSIS
        Retrieves information about Action1 applications with interactive drill-down.

    .DESCRIPTION
        Lists applications or gets details about a specific application from Action1.
        If no OrganizationId is provided, prompts user to select from available organizations,
        then allows drilling down into repos, apps, and versions.

    .PARAMETER OrganizationId
        Action1 organization ID. If not specified, prompts user to select.

    .PARAMETER PackageId
        Specific package/repo ID to retrieve.

    .PARAMETER VersionId
        Specific version ID to retrieve (requires PackageId).

    .PARAMETER Name
        Filter by application name.

    .PARAMETER NoInteractive
        Disable interactive drill-down mode. By default, when no parameters are provided,
        interactive mode is enabled to browse repos → versions.

    .EXAMPLE
        Get-Action1AppPackage
        # Full interactive drill-down through org → repo → version

    .EXAMPLE
        Get-Action1AppPackage -NoInteractive
        # Returns repos list without drill-down prompts

    .EXAMPLE
        Get-Action1AppPackage -OrganizationId "org123" -Name "7-Zip"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$PackageId,

        [Parameter()]
        [string]$VersionId,

        [Parameter()]
        [string]$Name,

        [Parameter()]
        [switch]$NoInteractive
    )

    try {
        # If no OrganizationId provided, prompt for selection
        if (-not $OrganizationId) {
            $selectedOrg = Select-Action1Organization -IncludeAll $true
            if (-not $selectedOrg) {
                throw "No organization selected."
            }
            $OrganizationId = $selectedOrg.Id
        }

        # If specific version requested
        if ($PackageId -and $VersionId) {
            $version = Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId/$PackageId/versions/$VersionId" `
                -Method GET
            return ($version | Expand-NestedJsonAttributes -ExpandFileNames -FormatNested)
        }

        # If specific package requested (list versions)
        if ($PackageId) {
            # Fetch package with all fields to get embedded versions array
            $response = Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId/$PackageId?fields=*" `
                -Method GET

            $versions = if ($response.versions) { @($response.versions) } else { @() }
            return ($versions | Expand-NestedJsonAttributes -ExpandFileNames -FormatNested)
        }

        # Get repos list
        $response = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId`?custom=yes&builtin=no&limit=100" `
            -Method GET

        $repos = if ($response.items) { @($response.items) } else { @($response) }

        if ($Name) {
            $repos = $repos | Where-Object { $_.name -like "*$Name*" }
        }

        # If NoInteractive flag set, just return the repos
        if ($NoInteractive) {
            return $repos
        }

        # Interactive mode - drill down through repos → versions
        if ($repos.Count -eq 0) {
            Write-Host "`nNo repositories found." -ForegroundColor Yellow
            return @()
        }

        # Select a repo
        Write-Host "`nSelect Repository:" -ForegroundColor Cyan
        Write-Host "  [0] Return all repositories (no drill-down)"
        for ($i = 0; $i -lt $repos.Count; $i++) {
            $repo = $repos[$i]
            $platform = if ($repo.platform) { " [$($repo.platform)]" } else { "" }
            Write-Host "  [$($i + 1)] $($repo.name)$platform - $($repo.vendor)"
        }

        $repoSelection = Read-Host "`nEnter selection (0-$($repos.Count))"
        $repoNum = [int]$repoSelection

        if ($repoNum -eq 0) {
            return $repos
        }

        if ($repoNum -lt 1 -or $repoNum -gt $repos.Count) {
            throw "Invalid selection."
        }

        $selectedRepo = $repos[$repoNum - 1]
        Write-Host "Selected: $($selectedRepo.name)" -ForegroundColor Green

        # Fetch package with all fields to get embedded versions array
        Write-Action1Log "Fetching versions for $($selectedRepo.name)..." -Level INFO
        $packageResponse = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId/$($selectedRepo.id)?fields=*" `
            -Method GET

        # Versions are embedded in the package response when using fields=*
        $versions = if ($packageResponse.versions) {
            @($packageResponse.versions)  # Force array in case of single item
        } else {
            @()
        }

        Write-Action1Log "Found $($versions.Count) version(s)" -Level DEBUG

        if ($versions.Count -eq 0) {
            Write-Host "`nNo versions found for this repository." -ForegroundColor Yellow
            return $selectedRepo
        }

        # Select a version
        Write-Host "`nSelect Version:" -ForegroundColor Cyan
        Write-Host "  [0] Return all versions (no drill-down)"
        for ($i = 0; $i -lt $versions.Count; $i++) {
            $ver = $versions[$i]
            $status = if ($ver.status) { " ($($ver.status))" } else { "" }
            $date = if ($ver.release_date) { " - $($ver.release_date)" } else { "" }
            Write-Host "  [$($i + 1)] v$($ver.version)$status$date"
        }

        $verSelection = Read-Host "`nEnter selection (0-$($versions.Count))"
        $verNum = [int]$verSelection

        if ($verNum -eq 0) {
            return ($versions | Expand-NestedJsonAttributes -ExpandFileNames -FormatNested)
        }

        if ($verNum -lt 1 -or $verNum -gt $versions.Count) {
            throw "Invalid selection."
        }

        $selectedVersion = $versions[$verNum - 1]
        Write-Host "Selected: v$($selectedVersion.version)" -ForegroundColor Green

        # Fetch full version details
        Write-Action1Log "Fetching version details..." -Level INFO
        $versionDetails = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId/$($selectedRepo.id)/versions/$($selectedVersion.id)" `
            -Method GET

        return ($versionDetails | Expand-NestedJsonAttributes -ExpandFileNames -FormatNested)
    }
    catch {
        Write-Error "Failed to retrieve applications: $($_.Exception.Message)"
    }
}

function Get-Action1AppRepo {
    <#
    .SYNOPSIS
        Gets information about a local application repository.

    .DESCRIPTION
        Scans a local application repository folder (vendor/app level) and returns
        information about all available package versions, including their manifests
        and installer files.

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

    .EXAMPLE
        Get-Action1AppRepo -Path ".\Microsoft\PowerShell"
        # Gets all versions of PowerShell from the specified path

    .EXAMPLE
        Get-Action1AppRepo -Vendor "Microsoft" -AppName "PowerShell"
        # Gets all versions using vendor/app name lookup from current directory

    .EXAMPLE
        Get-Action1AppRepo -BasePath "C:\Packages" -Vendor "7-Zip" -AppName "7-Zip"
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPath')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByPath', Position = 0)]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Vendor,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$AppName,

        [Parameter(ParameterSetName = 'ByName')]
        [string]$BasePath = (Get-Location).Path
    )

    try {
        # Determine the app repo path
        if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
            $appRepoPath = $Path
        }
        else {
            # Sanitize names for folder lookup (remove punctuation, replace spaces with underscores)
            $sanitizedVendor = $Vendor -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
            $sanitizedApp = $AppName -replace '[\\/:*?"<>|.,;''!&()]', '' -replace '\s+', '_'
            $appRepoPath = Join-Path $BasePath $sanitizedVendor $sanitizedApp
        }

        if (-not (Test-Path $appRepoPath -PathType Container)) {
            throw "Application repository not found: $appRepoPath"
        }

        Write-Host "`n=== Application Repository Information ===" -ForegroundColor Cyan
        Write-Host "Path: $appRepoPath" -ForegroundColor Gray

        # Get all version folders
        $versionFolders = Get-ChildItem -Path $appRepoPath -Directory -ErrorAction SilentlyContinue

        if ($versionFolders.Count -eq 0) {
            Write-Host "No version folders found." -ForegroundColor Yellow
            return @{
                Path = $appRepoPath
                Versions = @()
            }
        }

        # Collect information about each version
        $versions = @()
        $appName = $null
        $publisher = $null

        foreach ($versionFolder in $versionFolders) {
            $manifestPath = Join-Path $versionFolder.FullName "manifest.json"

            if (Test-Path $manifestPath) {
                $manifest = Read-ManifestFile -Path $manifestPath

                # Get app info from first manifest
                if (-not $appName -and $manifest.AppName) {
                    $appName = $manifest.AppName
                    $publisher = $manifest.Publisher
                }

                # Count installers
                $installerCount = 0
                $architectures = @()

                if ($manifest.Installers -and $manifest.Installers.Count -gt 0) {
                    $installerCount = $manifest.Installers.Count
                    $architectures = $manifest.Installers | ForEach-Object { $_.Architecture }
                }

                $versions += [PSCustomObject]@{
                    Version = $manifest.Version
                    ReleaseDate = $manifest.ReleaseDate
                    InstallerType = $manifest.InstallerType
                    InstallerCount = $installerCount
                    Architectures = ($architectures -join ', ')
                    ManifestPath = $manifestPath
                    FolderPath = $versionFolder.FullName
                    Manifest = $manifest
                }
            }
            else {
                Write-Action1Log "No manifest found in: $($versionFolder.FullName)" -Level WARN
            }
        }

        # Sort versions (attempt semantic versioning sort)
        $versions = $versions | Sort-Object {
            try {
                [version]$_.Version
            }
            catch {
                $_.Version
            }
        } -Descending

        # Display summary
        Write-Host "`nApplication: $appName" -ForegroundColor Green
        Write-Host "Publisher: $publisher" -ForegroundColor Green
        Write-Host "Total Versions: $($versions.Count)" -ForegroundColor Green

        Write-Host "`n--- Available Versions ---" -ForegroundColor Cyan
        foreach ($ver in $versions) {
            $archInfo = if ($ver.Architectures) { " [$($ver.Architectures)]" } else { "" }
            Write-Host "  v$($ver.Version) - $($ver.ReleaseDate)$archInfo"
        }

        return [PSCustomObject]@{
            Path = $appRepoPath
            AppName = $appName
            Publisher = $publisher
            VersionCount = $versions.Count
            Versions = $versions
        }
    }
    catch {
        Write-Error "Failed to get application repository info: $($_.Exception.Message)"
    }
}

function Get-Action1Organization {
    <#
    .SYNOPSIS
        Retrieves organizations from Action1.

    .DESCRIPTION
        Lists all organizations the authenticated user has access to.

    .EXAMPLE
        Get-Action1Organization
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Action1Log "Fetching organizations..." -Level INFO
        $response = Invoke-Action1ApiRequest -Endpoint "organizations" -Method GET
        $orgs = if ($response.items) { @($response.items) } else { @($response) }
        return $orgs
    }
    catch {
        Write-Error "Failed to retrieve organizations: $($_.Exception.Message)"
    }
}

# FIXME: Fails to retrieve endpoint groups due to json parsing error
# Get-Action1EndpointGroup: Failed to retrieve endpoint groups: Conversion from JSON failed with error: Additional text encountered after finished reading JSON content: F. Path '', line 3, position 4.
function Get-Action1EndpointGroup {
    <#
    .SYNOPSIS
        Retrieves endpoint groups from Action1.

    .DESCRIPTION
        Lists endpoint groups for an organization. If no OrganizationId is provided,
        prompts user to select from available organizations.

    .PARAMETER OrganizationId
        Action1 organization ID. If not specified, prompts user to select.

    .PARAMETER GroupId
        Specific group ID to retrieve details for.

    .PARAMETER Name
        Filter groups by name.

    .EXAMPLE
        Get-Action1EndpointGroup
        # Interactive selection of organization then lists groups

    .EXAMPLE
        Get-Action1EndpointGroup -OrganizationId "org123" -Name "Servers"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$GroupId,

        [Parameter()]
        [string]$Name
    )

    try {
        # If no OrganizationId provided, prompt for selection
        if (-not $OrganizationId) {
            $selectedOrg = Select-Action1Organization -IncludeAll $false
            if (-not $selectedOrg) {
                throw "No organization selected."
            }
            $OrganizationId = $selectedOrg.Id
        }

        # If specific group requested
        if ($GroupId) {
            $group = Invoke-Action1ApiRequest `
                -Endpoint "organizations/$OrganizationId/endpoint_groups/$GroupId" `
                -Method GET
            return $group
        }

        # List all groups
        Write-Action1Log "Fetching endpoint groups for organization $OrganizationId..." -Level INFO
        $response = Invoke-Action1ApiRequest `
            -Endpoint "organizations/$OrganizationId/endpoint_groups?limit=100" `
            -Method GET

        $groups = if ($response.items) { $response.items } else { @($response) }

        if ($Name) {
            $groups = $groups | Where-Object { $_.name -like "*$Name*" }
        }

        return $groups
    }
    catch {
        Write-Error "Failed to retrieve endpoint groups: $($_.Exception.Message)"
    }
}

# TODO: Test function
function New-Action1EndpointGroup {
    <#
    .SYNOPSIS
        Creates a new endpoint group in Action1.

    .DESCRIPTION
        Creates an endpoint group with the specified configuration.

    .PARAMETER OrganizationId
        Action1 organization ID.

    .PARAMETER Name
        Name of the endpoint group.

    .PARAMETER Description
        Description of the endpoint group.

    .PARAMETER Filter
        Dynamic filter criteria for the group (optional).

    .EXAMPLE
        New-Action1EndpointGroup -OrganizationId "org123" -Name "Windows Servers" -Description "All Windows Server endpoints"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationId,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Description = "",

        [Parameter()]
        [hashtable]$Filter
    )

    try {
        Write-Action1Log "Creating endpoint group: $Name" -Level INFO

        $groupData = @{
            name = $Name
            description = $Description
        }

        if ($Filter) {
            $groupData['filter'] = $Filter
        }

        $response = Invoke-Action1ApiRequest `
            -Endpoint "organizations/$OrganizationId/endpoint_groups" `
            -Method POST `
            -Body $groupData

        Write-Host "Endpoint group created: $($response.name) (ID: $($response.id))" -ForegroundColor Green
        return $response
    }
    catch {
        Write-Error "Failed to create endpoint group: $($_.Exception.Message)"
    }
}

# TODO: Test function
function Get-Action1Automation {
    <#
    .SYNOPSIS
        Retrieves automations (policies) from Action1.

    .DESCRIPTION
        Lists automations for an organization with interactive drill-down.
        If no OrganizationId is provided, prompts user to select from available organizations.

    .PARAMETER OrganizationId
        Action1 organization ID. If not specified, prompts user to select.

    .PARAMETER AutomationId
        Specific automation ID to retrieve details for.

    .PARAMETER Name
        Filter automations by name.

    .PARAMETER NoInteractive
        Disable interactive mode. By default, allows selecting an automation for details.

    .EXAMPLE
        Get-Action1Automation
        # Interactive selection of organization and automation

    .EXAMPLE
        Get-Action1Automation -OrganizationId "org123" -NoInteractive
        # Returns all automations without prompts
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$AutomationId,

        [Parameter()]
        [string]$Name,

        [Parameter()]
        [switch]$NoInteractive
    )

    try {
        # If no OrganizationId provided, prompt for selection
        if (-not $OrganizationId) {
            $selectedOrg = Select-Action1Organization -IncludeAll $false
            if (-not $selectedOrg) {
                throw "No organization selected."
            }
            $OrganizationId = $selectedOrg.Id
        }

        # If specific automation requested
        if ($AutomationId) {
            Write-Action1Log "Fetching automation details: $AutomationId" -Level INFO
            $automation = Invoke-Action1ApiRequest `
                -Endpoint "organizations/$OrganizationId/automations/$AutomationId" `
                -Method GET
            return $automation
        }

        # List all automations
        Write-Action1Log "Fetching automations for organization $OrganizationId..." -Level INFO
        $response = Invoke-Action1ApiRequest `
            -Endpoint "organizations/$OrganizationId/automations?limit=100" `
            -Method GET

        $automations = if ($response.items) { $response.items } else { @($response) }

        if ($Name) {
            $automations = $automations | Where-Object { $_.name -like "*$Name*" }
        }

        # If NoInteractive, just return the list
        if ($NoInteractive) {
            return $automations
        }

        # Interactive mode - allow selecting an automation for details
        if ($automations.Count -eq 0) {
            Write-Host "`nNo automations found." -ForegroundColor Yellow
            return @()
        }

        Write-Host "`nSelect Automation:" -ForegroundColor Cyan
        Write-Host "  [0] Return all automations (no drill-down)"
        for ($i = 0; $i -lt $automations.Count; $i++) {
            $auto = $automations[$i]
            $status = if ($auto.enabled) { "[Enabled]" } else { "[Disabled]" }
            $trigger = if ($auto.trigger_type) { "($($auto.trigger_type))" } else { "" }
            Write-Host "  [$($i + 1)] $($auto.name) $status $trigger"
        }

        $autoSelection = Read-Host "`nEnter selection (0-$($automations.Count))"
        $autoNum = [int]$autoSelection

        if ($autoNum -eq 0) {
            return $automations
        }

        if ($autoNum -lt 1 -or $autoNum -gt $automations.Count) {
            throw "Invalid selection."
        }

        $selectedAutomation = $automations[$autoNum - 1]
        Write-Host "Selected: $($selectedAutomation.name)" -ForegroundColor Green

        # Fetch full automation details
        Write-Action1Log "Fetching automation details..." -Level INFO
        $automationDetails = Invoke-Action1ApiRequest `
            -Endpoint "organizations/$OrganizationId/automations/$($selectedAutomation.id)" `
            -Method GET

        return $automationDetails
    }
    catch {
        Write-Error "Failed to retrieve automations: $($_.Exception.Message)"
    }
}

# TODO: Test function
function Copy-Action1Automation {
    <#
    .SYNOPSIS
        Copies automations between Action1 organizations.

    .DESCRIPTION
        Clones one or more automations from a source organization to one or more
        destination organizations. If endpoint groups referenced by the automation
        don't exist in the destination, they will be created.

    .PARAMETER SourceOrgId
        Source organization ID. If not specified, prompts for selection.

    .PARAMETER DestinationOrgIds
        Array of destination organization IDs. If not specified, prompts for selection.

    .PARAMETER AutomationIds
        Array of automation IDs to copy. If not specified, prompts for selection.

    .PARAMETER IncludeGroups
        If specified, copies referenced endpoint groups to destinations (default: $true).

    .EXAMPLE
        Copy-Action1Automation
        # Fully interactive - prompts for source org, automations, and destinations

    .EXAMPLE
        Copy-Action1Automation -SourceOrgId "org1" -DestinationOrgIds @("org2", "org3") -AutomationIds @("auto1")
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SourceOrgId,

        [Parameter()]
        [string[]]$DestinationOrgIds,

        [Parameter()]
        [string[]]$AutomationIds,

        [Parameter()]
        [bool]$IncludeGroups = $true
    )

    try {
        # Get all organizations first
        $orgs = Get-Action1Organization
        if ($orgs.Count -lt 2) {
            throw "At least 2 organizations are required to copy automations between them."
        }

        # Select source organization
        if (-not $SourceOrgId) {
            Write-Host "`nSelect Source Organization:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $orgs.Count; $i++) {
                Write-Host "  [$($i + 1)] $($orgs[$i].name)"
            }

            $selection = Read-Host "`nEnter selection (1-$($orgs.Count))"
            $selNum = [int]$selection

            if ($selNum -lt 1 -or $selNum -gt $orgs.Count) {
                throw "Invalid selection."
            }

            $SourceOrgId = $orgs[$selNum - 1].id
            $sourceOrgName = $orgs[$selNum - 1].name
            Write-Host "Selected: $sourceOrgName" -ForegroundColor Green
        }
        else {
            $sourceOrgName = ($orgs | Where-Object { $_.id -eq $SourceOrgId }).name
        }

        # Get automations from source
        Write-Action1Log "Fetching automations from source organization..." -Level INFO
        $automations = Get-Action1Automation -OrganizationId $SourceOrgId -NoInteractive

        if ($automations.Count -eq 0) {
            Write-Host "No automations found in source organization." -ForegroundColor Yellow
            return
        }

        # Select automations to copy
        if (-not $AutomationIds) {
            Write-Host "`nSelect Automations to Copy:" -ForegroundColor Cyan
            Write-Host "  [0] ALL automations"
            for ($i = 0; $i -lt $automations.Count; $i++) {
                $auto = $automations[$i]
                $status = if ($auto.enabled) { "[Enabled]" } else { "[Disabled]" }
                Write-Host "  [$($i + 1)] $($auto.name) $status"
            }

            $autoInput = Read-Host "`nEnter selection (0-$($automations.Count), comma-separated for multiple)"

            if ($autoInput -eq '0') {
                $AutomationIds = $automations | ForEach-Object { $_.id }
                Write-Host "Selected: ALL automations ($($AutomationIds.Count) total)" -ForegroundColor Green
            }
            else {
                $selections = $autoInput -split ',' | ForEach-Object { [int]$_.Trim() }
                $AutomationIds = @()
                foreach ($sel in $selections) {
                    if ($sel -ge 1 -and $sel -le $automations.Count) {
                        $AutomationIds += $automations[$sel - 1].id
                    }
                }
                Write-Host "Selected: $($AutomationIds.Count) automation(s)" -ForegroundColor Green
            }
        }

        # Select destination organizations
        if (-not $DestinationOrgIds) {
            Write-Host "`nSelect Destination Organization(s):" -ForegroundColor Cyan
            Write-Host "  [0] ALL other organizations"
            $otherOrgs = $orgs | Where-Object { $_.id -ne $SourceOrgId }
            for ($i = 0; $i -lt $otherOrgs.Count; $i++) {
                Write-Host "  [$($i + 1)] $($otherOrgs[$i].name)"
            }

            $destInput = Read-Host "`nEnter selection (0-$($otherOrgs.Count), comma-separated for multiple)"

            if ($destInput -eq '0') {
                $DestinationOrgIds = $otherOrgs | ForEach-Object { $_.id }
                Write-Host "Selected: ALL other organizations ($($DestinationOrgIds.Count) total)" -ForegroundColor Green
            }
            else {
                $selections = $destInput -split ',' | ForEach-Object { [int]$_.Trim() }
                $DestinationOrgIds = @()
                foreach ($sel in $selections) {
                    if ($sel -ge 1 -and $sel -le $otherOrgs.Count) {
                        $DestinationOrgIds += $otherOrgs[$sel - 1].id
                    }
                }
                Write-Host "Selected: $($DestinationOrgIds.Count) destination(s)" -ForegroundColor Green
            }
        }

        # Confirm the operation
        Write-Host "`nCopy Summary:" -ForegroundColor Yellow
        Write-Host "Source: $sourceOrgName"
        Write-Host "Automations: $($AutomationIds.Count)"
        Write-Host "Destinations: $($DestinationOrgIds.Count) organization(s)"
        Write-Host "Include Groups: $IncludeGroups"

        $confirm = Read-Host "`nProceed with copy? (Y/n)"
        if ($confirm -eq 'n' -or $confirm -eq 'N') {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            return
        }

        # Process each automation
        $results = @()
        $totalOperations = $AutomationIds.Count * $DestinationOrgIds.Count
        $currentOp = 0

        foreach ($autoId in $AutomationIds) {
            # Get full automation details
            Write-Action1Log "Fetching automation details: $autoId" -Level INFO
            $automation = Get-Action1Automation -OrganizationId $SourceOrgId -AutomationId $autoId

            Write-Host "`nProcessing: $($automation.name)" -ForegroundColor Cyan

            # Get referenced endpoint groups from the automation
            $referencedGroupIds = @()
            if ($automation.endpoint_group_id) {
                $referencedGroupIds += $automation.endpoint_group_id
            }
            if ($automation.endpoint_groups) {
                $referencedGroupIds += $automation.endpoint_groups | ForEach-Object { $_.id }
            }

            # Get group details from source if we need to copy them
            $sourceGroups = @{}
            if ($IncludeGroups -and $referencedGroupIds.Count -gt 0) {
                foreach ($groupId in $referencedGroupIds) {
                    try {
                        $group = Get-Action1EndpointGroup -OrganizationId $SourceOrgId -GroupId $groupId
                        $sourceGroups[$groupId] = $group
                        Write-Action1Log "Found referenced group: $($group.name)" -Level DEBUG
                    }
                    catch {
                        Write-Action1Log "Could not fetch group $groupId" -Level WARN
                    }
                }
            }

            # Copy to each destination
            foreach ($destOrgId in $DestinationOrgIds) {
                $currentOp++
                $destOrgName = ($orgs | Where-Object { $_.id -eq $destOrgId }).name
                $percentComplete = [int](($currentOp / $totalOperations) * 100)

                Write-Progress -Activity "Copying Automations" -Status "Copying '$($automation.name)' to $destOrgName" -PercentComplete $percentComplete

                Write-Host "  -> $destOrgName" -ForegroundColor Gray

                try {
                    # Map group IDs - check if groups exist in destination, create if not
                    $groupIdMapping = @{}
                    if ($IncludeGroups -and $sourceGroups.Count -gt 0) {
                        # Get existing groups in destination
                        $destGroups = Get-Action1EndpointGroup -OrganizationId $destOrgId

                        foreach ($srcGroupId in $sourceGroups.Keys) {
                            $srcGroup = $sourceGroups[$srcGroupId]

                            # Check if group with same name exists
                            $existingGroup = $destGroups | Where-Object { $_.name -eq $srcGroup.name } | Select-Object -First 1

                            if ($existingGroup) {
                                Write-Action1Log "Group '$($srcGroup.name)' already exists in destination" -Level DEBUG
                                $groupIdMapping[$srcGroupId] = $existingGroup.id
                            }
                            else {
                                # Create the group in destination
                                Write-Host "    Creating group: $($srcGroup.name)" -ForegroundColor DarkGray
                                $newGroup = New-Action1EndpointGroup `
                                    -OrganizationId $destOrgId `
                                    -Name $srcGroup.name `
                                    -Description $srcGroup.description

                                $groupIdMapping[$srcGroupId] = $newGroup.id
                            }
                        }
                    }

                    # Prepare automation data for creation
                    $newAutomationData = @{
                        name = $automation.name
                        description = if ($automation.description) { $automation.description } else { "" }
                        enabled = $automation.enabled
                    }

                    # Copy relevant properties
                    if ($automation.trigger_type) {
                        $newAutomationData['trigger_type'] = $automation.trigger_type
                    }
                    if ($automation.trigger) {
                        $newAutomationData['trigger'] = $automation.trigger
                    }
                    if ($automation.actions) {
                        $newAutomationData['actions'] = $automation.actions
                    }
                    if ($automation.schedule) {
                        $newAutomationData['schedule'] = $automation.schedule
                    }

                    # Update endpoint group references with mapped IDs
                    if ($automation.endpoint_group_id -and $groupIdMapping.ContainsKey($automation.endpoint_group_id)) {
                        $newAutomationData['endpoint_group_id'] = $groupIdMapping[$automation.endpoint_group_id]
                    }
                    elseif ($automation.endpoint_group_id) {
                        $newAutomationData['endpoint_group_id'] = $automation.endpoint_group_id
                    }

                    # Create the automation in destination
                    Write-Action1Log "Creating automation in destination..." -Level DEBUG
                    $response = Invoke-Action1ApiRequest `
                        -Endpoint "organizations/$destOrgId/automations" `
                        -Method POST `
                        -Body $newAutomationData

                    Write-Host "    Created: $($response.id)" -ForegroundColor Green

                    $results += @{
                        SourceAutomation = $automation.name
                        SourceAutomationId = $autoId
                        DestinationOrg = $destOrgName
                        DestinationOrgId = $destOrgId
                        NewAutomationId = $response.id
                        Status = 'Success'
                        GroupsCopied = $groupIdMapping.Count
                    }
                }
                catch {
                    Write-Host "    Failed: $($_.Exception.Message)" -ForegroundColor Red
                    $results += @{
                        SourceAutomation = $automation.name
                        SourceAutomationId = $autoId
                        DestinationOrg = $destOrgName
                        DestinationOrgId = $destOrgId
                        NewAutomationId = $null
                        Status = 'Failed'
                        Error = $_.Exception.Message
                    }
                }
            }
        }

        Write-Progress -Activity "Copying Automations" -Completed

        # Summary
        Write-Host "`n=== Copy Results ===" -ForegroundColor Green
        $successCount = ($results | Where-Object { $_.Status -eq 'Success' }).Count
        $failCount = ($results | Where-Object { $_.Status -eq 'Failed' }).Count

        Write-Host "Successful: $successCount" -ForegroundColor Green
        if ($failCount -gt 0) {
            Write-Host "Failed: $failCount" -ForegroundColor Red
        }

        return $results
    }
    catch {
        Write-Error "Failed to copy automations: $($_.Exception.Message)"
    }
}

function Remove-Action1AppPackage {
    <#
    .SYNOPSIS
        Removes a package version from an Action1 software repository.

    .DESCRIPTION
        Interactively selects and deletes a specific package version from a software
        repository in Action1. Uses the same drill-down selector pattern as Get-Action1AppPackage.

    .PARAMETER OrganizationId
        Action1 organization ID. If not provided, prompts for selection.

    .PARAMETER PackageId
        Package ID. If not provided, prompts for selection.

    .PARAMETER VersionId
        Version ID to remove. If not provided, prompts for selection.

    .PARAMETER Force
        Skips confirmation prompt.

    .EXAMPLE
        Remove-Action1AppPackage
        # Interactive mode - prompts for org, repo, and version selection

    .EXAMPLE
        Remove-Action1AppPackage -OrganizationId "all" -PackageId "pkg123" -VersionId "ver456" -Force
        # Direct removal without prompts
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$PackageId,

        [Parameter()]
        [string]$VersionId,

        [Parameter()]
        [switch]$Force
    )

    try {
        # Step 1: Select organization
        if (-not $OrganizationId) {
            $selectedOrg = Select-Action1Organization -IncludeAll $true
            if (-not $selectedOrg) {
                Write-Host "Operation cancelled." -ForegroundColor Yellow
                return
            }
            $OrganizationId = $selectedOrg.Id
        }

        # Step 2: Select repository if not provided
        if (-not $PackageId) {
            Write-Host "`nFetching repositories..." -ForegroundColor Gray
            $response = Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId`?custom=yes&builtin=no&limit=100" `
                -Method GET

            $repos = if ($response.items) { @($response.items) } else { @($response) }

            if ($repos.Count -eq 0) {
                Write-Host "`nNo repositories found." -ForegroundColor Yellow
                return
            }

            Write-Host "`nSelect Repository:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $repos.Count; $i++) {
                $repo = $repos[$i]
                $platform = if ($repo.platform) { " [$($repo.platform)]" } else { "" }
                Write-Host "  [$i] $($repo.name)$platform - $($repo.vendor)"
            }

            $repoSelection = Read-Host "`nEnter selection (0-$($repos.Count - 1))"
            $repoNum = [int]$repoSelection

            if ($repoNum -lt 0 -or $repoNum -ge $repos.Count) {
                Write-Host "Invalid selection." -ForegroundColor Red
                return
            }

            $selectedRepo = $repos[$repoNum]
            Write-Host "Selected: $($selectedRepo.name)" -ForegroundColor Green
            $PackageId = $selectedRepo.id
        }

        # Step 3: Select version if not provided
        if (-not $VersionId) {
            Write-Host "`nFetching versions..." -ForegroundColor Gray
            $packageResponse = Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId/$PackageId`?fields=*" `
                -Method GET

            $versions = if ($packageResponse.versions) { @($packageResponse.versions) } else { @() }

            if ($versions.Count -eq 0) {
                Write-Host "`nNo versions found for this repository." -ForegroundColor Yellow
                return
            }

            Write-Host "`nSelect Version to Remove:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $versions.Count; $i++) {
                $ver = $versions[$i]
                $status = if ($ver.status) { " ($($ver.status))" } else { "" }
                $date = if ($ver.release_date) { " - $($ver.release_date)" } else { "" }
                Write-Host "  [$i] v$($ver.version)$status$date"
            }

            $verSelection = Read-Host "`nEnter selection (0-$($versions.Count - 1))"
            $verNum = [int]$verSelection

            if ($verNum -lt 0 -or $verNum -ge $versions.Count) {
                Write-Host "Invalid selection." -ForegroundColor Red
                return
            }

            $selectedVersion = $versions[$verNum]
            Write-Host "Selected: v$($selectedVersion.version)" -ForegroundColor Green
            $VersionId = $selectedVersion.id
        }

        # Get version info for confirmation
        $versionInfo = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId/$PackageId/versions/$VersionId" `
            -Method GET

        $confirmMsg = "version $($versionInfo.version) from package $PackageId"

        if ($Force -or $PSCmdlet.ShouldProcess($confirmMsg, "Remove")) {
            if (-not $Force) {
                Write-Host "`n⚠ WARNING: This will permanently delete version '$($versionInfo.version)'!" -ForegroundColor Red
                $confirm = Read-Host "Type 'DELETE' to confirm"
                if ($confirm -ne 'DELETE') {
                    Write-Host "Operation cancelled." -ForegroundColor Yellow
                    return
                }
            }

            Write-Host "`nDeleting version..." -ForegroundColor Yellow
            Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId/$PackageId/versions/$VersionId" `
                -Method DELETE

            Write-Host "✓ Version '$($versionInfo.version)' removed successfully" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to remove package version: $($_.Exception.Message)"
    }
}

function Remove-Action1AppRepo {
    <#
    .SYNOPSIS
        Removes an entire software repository from Action1.

    .DESCRIPTION
        Interactively selects and deletes an entire software repository package
        from Action1, including all versions and files.

    .PARAMETER OrganizationId
        Action1 organization ID. If not provided, prompts for selection.

    .PARAMETER PackageId
        Package ID to remove. If not provided, prompts for selection.

    .PARAMETER Force
        Skips confirmation prompt.

    .EXAMPLE
        Remove-Action1AppRepo
        # Interactive mode - prompts for org and repo selection

    .EXAMPLE
        Remove-Action1AppRepo -OrganizationId "all" -PackageId "pkg123" -Force
        # Direct removal without prompts
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter()]
        [string]$OrganizationId,

        [Parameter()]
        [string]$PackageId,

        [Parameter()]
        [switch]$Force
    )

    try {
        # Step 1: Select organization
        if (-not $OrganizationId) {
            $selectedOrg = Select-Action1Organization -IncludeAll $true
            if (-not $selectedOrg) {
                Write-Host "Operation cancelled." -ForegroundColor Yellow
                return
            }
            $OrganizationId = $selectedOrg.Id
        }

        # Step 2: Select repository if not provided
        if (-not $PackageId) {
            Write-Host "`nFetching repositories..." -ForegroundColor Gray
            $response = Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId`?custom=yes&builtin=no&limit=100" `
                -Method GET

            $repos = if ($response.items) { @($response.items) } else { @($response) }

            if ($repos.Count -eq 0) {
                Write-Host "`nNo repositories found." -ForegroundColor Yellow
                return
            }

            Write-Host "`nSelect Repository to Delete:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $repos.Count; $i++) {
                $repo = $repos[$i]
                $platform = if ($repo.platform) { " [$($repo.platform)]" } else { "" }
                Write-Host "  [$i] $($repo.name)$platform - $($repo.vendor)"
            }

            $repoSelection = Read-Host "`nEnter selection (0-$($repos.Count - 1))"
            $repoNum = [int]$repoSelection

            if ($repoNum -lt 0 -or $repoNum -ge $repos.Count) {
                Write-Host "Invalid selection." -ForegroundColor Red
                return
            }

            $selectedRepo = $repos[$repoNum]
            Write-Host "Selected: $($selectedRepo.name)" -ForegroundColor Green
            $PackageId = $selectedRepo.id
        }

        # Get full repo info for confirmation
        $repoInfo = Invoke-Action1ApiRequest `
            -Endpoint "software-repository/$OrganizationId/$PackageId`?fields=*" `
            -Method GET

        $versionCount = if ($repoInfo.versions) { $repoInfo.versions.Count } else { 0 }
        $confirmMsg = "repository '$($repoInfo.name)' ($versionCount versions)"

        if ($Force -or $PSCmdlet.ShouldProcess($confirmMsg, "Remove")) {
            if (-not $Force) {
                Write-Host "`n⚠ WARNING: This will permanently delete the entire repository!" -ForegroundColor Red
                Write-Host "  Repository: $($repoInfo.name)" -ForegroundColor White
                Write-Host "  Vendor: $($repoInfo.vendor)" -ForegroundColor White
                Write-Host "  Versions: $versionCount" -ForegroundColor White
                Write-Host "`nAll versions and uploaded files will be permanently deleted." -ForegroundColor Red
                $confirm = Read-Host "Type 'DELETE' to confirm"
                if ($confirm -ne 'DELETE') {
                    Write-Host "Operation cancelled." -ForegroundColor Yellow
                    return
                }
            }

            Write-Host "`nDeleting repository..." -ForegroundColor Yellow
            Invoke-Action1ApiRequest `
                -Endpoint "software-repository/$OrganizationId/$PackageId" `
                -Method DELETE

            Write-Host "✓ Repository '$($repoInfo.name)' and all versions removed successfully" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to remove repository: $($_.Exception.Message)"
    }
}

# TODO: Add function Update-Action1AppPackage
# TODO: Add function Update-Action1AppRepo
# TODO: Add function Export-Action1AppRepo
# TODO: Add function Export-Action1AppPackage


# Module initialization
Write-Verbose "Action1.Tools module loaded"

# Try to load saved credentials if they exist
$credPath = Join-Path $script:Action1ConfigDir "credentials.json"

if (Test-Path $credPath) {
    try {
        $savedCreds = Get-Content $credPath -Raw | ConvertFrom-Json

        # Support both old (ApiKey/Secret) and new (ClientId/ClientSecret) formats
        if ($savedCreds.ClientId) {
            $script:Action1ClientId = $savedCreds.ClientId
            $script:Action1ClientSecret = $savedCreds.ClientSecret
            $script:Action1Region = $savedCreds.Region ?? 'NorthAmerica'
        } elseif ($savedCreds.ApiKey) {
            # Legacy format support
            $script:Action1ClientId = $savedCreds.ApiKey
            $script:Action1ClientSecret = $savedCreds.Secret
            $script:Action1Region = 'NorthAmerica'
        }

        # Set the base URI based on region
        if ($script:Action1Region -and $script:Action1RegionUrls.ContainsKey($script:Action1Region)) {
            $script:Action1BaseUri = $script:Action1RegionUrls[$script:Action1Region]
        }

        Write-Verbose "Loaded saved Action1 credentials (Region: $($script:Action1Region))"
    }
    catch {
        Write-Verbose "Could not load saved credentials"
    }
}

# Register argument completers for tab completion
Register-ArgumentCompleter -CommandName New-Action1AppRepo -ParameterName Publisher -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $basePath = if ($fakeBoundParameters.ContainsKey('Path')) { $fakeBoundParameters['Path'] } else { (Get-Location).Path }
    $vendors = Get-ExistingVendors -BasePath $basePath

    $vendors | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName New-Action1AppRepo -ParameterName AppName -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $basePath = if ($fakeBoundParameters.ContainsKey('Path')) { $fakeBoundParameters['Path'] } else { (Get-Location).Path }
    $vendor = if ($fakeBoundParameters.ContainsKey('Publisher')) {
        $fakeBoundParameters['Publisher'] -replace '[\\/:*?"<>|]', '_' -replace '\s+', '_'
    } else { $null }

    if ($vendor) {
        $apps = Get-ExistingApps -BasePath $basePath -Vendor $vendor
        $apps | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

Register-ArgumentCompleter -CommandName New-Action1AppRepo -ParameterName Version -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $basePath = if ($fakeBoundParameters.ContainsKey('Path')) { $fakeBoundParameters['Path'] } else { (Get-Location).Path }
    $vendor = if ($fakeBoundParameters.ContainsKey('Publisher')) {
        $fakeBoundParameters['Publisher'] -replace '[\\/:*?"<>|]', '_' -replace '\s+', '_'
    } else { $null }
    $appName = if ($fakeBoundParameters.ContainsKey('AppName')) {
        $fakeBoundParameters['AppName'] -replace '[\\/:*?"<>|]', '_' -replace '\s+', '_'
    } else { $null }

    if ($vendor -and $appName) {
        $versions = Get-ExistingVersions -BasePath $basePath -Vendor $vendor -AppName $appName
        $versions | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

Export-ModuleMember -Function @(
    'Deploy-Action1AppPackage',
    'Deploy-Action1AppRepo',
    'Deploy-Action1AppUpdate',
    'New-Action1AppRepo',
    'New-Action1AppPackage',
    'Get-Action1AppPackage',
    'Get-Action1AppRepo',
    'Remove-Action1AppPackage',
    'Remove-Action1AppRepo',
    'Test-Action1Connection',
    'Set-Action1ApiCredentials',
    'Get-Action1ApiCredentials',
    'Set-Action1LogLevel',
    'Get-Action1LogLevel',
    'Get-Action1Organization',
    'Get-Action1EndpointGroup',
    'New-Action1EndpointGroup',
    'Get-Action1Automation',
    'Copy-Action1Automation'
)
