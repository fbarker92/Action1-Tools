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
