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
