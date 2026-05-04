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
