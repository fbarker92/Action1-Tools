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
        If specified, copies referenced endpoint groups to destinations (default: $false).
        Groups will be created in destination if they don't exist.

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
        [bool]$IncludeGroups = $false
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

        # Ask about including groups (only if not explicitly set via parameter)
        if (-not $PSBoundParameters.ContainsKey('IncludeGroups')) {
            Write-Host "`nInclude endpoint group assignments?" -ForegroundColor Cyan
            Write-Host "  If enabled, groups will be created in destinations if they don't exist."
            $groupInput = Read-Host "Include groups? (y/N)"
            if ($groupInput -eq 'y' -or $groupInput -eq 'Y') {
                $IncludeGroups = $true
                Write-Host "Groups will be included" -ForegroundColor Green
            }
            else {
                Write-Host "Groups will NOT be included" -ForegroundColor Yellow
            }
        }

        # Confirm the operation
        Write-Host "`nCopy Summary:" -ForegroundColor Yellow
        Write-Host "Source: $sourceOrgName"
        Write-Host "Automations: $($AutomationIds.Count)"
        Write-Host "Destinations: $($DestinationOrgIds.Count) organization(s)"
        if ($IncludeGroups) {
            Write-Host "Endpoint Groups: Will copy group assignments (create if needed)"
        }
        else {
            Write-Host "Endpoint Groups: Will target ALL endpoints (no group assignments)"
        }

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
            # Also check 'endpoints' array (API returns this for schedule-based automations)
            if ($automation.endpoints) {
                $referencedGroupIds += $automation.endpoints |
                    Where-Object { $_.type -eq 'EndpointGroup' } |
                    ForEach-Object { $_.id }
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
                    }

                    # Add description if present
                    if ($automation.description) {
                        $newAutomationData['description'] = $automation.description
                    }

                    # Copy schedule settings (for schedule-based automations)
                    if ($automation.settings) {
                        $newAutomationData['settings'] = $automation.settings
                    }
                    if ($automation.retry_minutes) {
                        $newAutomationData['retry_minutes'] = $automation.retry_minutes
                    }
                    if ($automation.settings_timezone) {
                        $newAutomationData['settings_timezone'] = $automation.settings_timezone
                    }
                    # Note: randomize_start is read-only and cannot be set via API

                    # Copy trigger properties
                    if ($automation.trigger_type) {
                        $newAutomationData['trigger_type'] = $automation.trigger_type
                    }
                    if ($automation.trigger) {
                        $newAutomationData['trigger'] = $automation.trigger
                    }

                    # Copy actions (remove source IDs so API generates new ones)
                    if ($automation.actions) {
                        $cleanActions = @()
                        foreach ($action in $automation.actions) {
                            $cleanAction = @{
                                name = $action.name
                                template_id = $action.template_id
                            }
                            if ($action.params) {
                                $cleanAction['params'] = $action.params
                            }
                            $cleanActions += $cleanAction
                        }
                        $newAutomationData['actions'] = $cleanActions
                    }

                    if ($automation.schedule) {
                        $newAutomationData['schedule'] = $automation.schedule
                    }

                    # Update endpoint group references with mapped IDs
                    if ($IncludeGroups) {
                        if ($automation.endpoint_group_id -and $groupIdMapping.ContainsKey($automation.endpoint_group_id)) {
                            $newAutomationData['endpoint_group_id'] = $groupIdMapping[$automation.endpoint_group_id]
                        }
                        elseif ($automation.endpoint_group_id) {
                            $newAutomationData['endpoint_group_id'] = $automation.endpoint_group_id
                        }

                        # Handle 'endpoints' array format (schedule-based automations)
                        if ($automation.endpoints -and $automation.endpoints.Count -gt 0) {
                            $mappedEndpoints = @()
                            foreach ($ep in $automation.endpoints) {
                                if ($ep.type -eq 'EndpointGroup' -and $groupIdMapping.ContainsKey($ep.id)) {
                                    $mappedEndpoints += @{
                                        id = $groupIdMapping[$ep.id]
                                        type = 'EndpointGroup'
                                    }
                                }
                                else {
                                    $mappedEndpoints += $ep
                                }
                            }
                            $newAutomationData['endpoints'] = $mappedEndpoints
                        }
                    }
                    else {
                        # Default to ALL endpoints when not copying groups
                        $newAutomationData['endpoints'] = @(
                            @{
                                id = 'ALL'
                                type = 'EndpointGroup'
                            }
                        )
                    }

                    # Create the automation in destination
                    Write-Action1Log "Creating automation in destination..." -Level DEBUG
                    $response = Invoke-Action1ApiRequest `
                        -Endpoint "policies/schedules/$destOrgId" `
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
