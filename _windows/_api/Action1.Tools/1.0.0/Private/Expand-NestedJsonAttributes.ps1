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
