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
