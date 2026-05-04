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
            -Endpoint "endpoints/groups/$OrganizationId" `
            -Method POST `
            -Body $groupData

        Write-Host "Endpoint group created: $($response.name) (ID: $($response.id))" -ForegroundColor Green
        return $response
    }
    catch {
        Write-Error "Failed to create endpoint group: $($_.Exception.Message)"
    }
}
