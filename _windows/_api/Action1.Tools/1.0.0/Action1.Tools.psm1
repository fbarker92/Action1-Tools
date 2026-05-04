#Requires -Version 7.0+

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
$script:Interactive = $true  # Global flag to enable/disable interactive prompts

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

# Dot-source all private functions first (public functions depend on them)
$Private = @(Get-ChildItem -Path "$PSScriptRoot/Private/*.ps1" -ErrorAction SilentlyContinue)
foreach ($import in $Private) {
    try { . $import.FullName }
    catch { Write-Error "Failed to import private function $($import.FullName): $_" }
}

# Dot-source all public functions
$Public = @(Get-ChildItem -Path "$PSScriptRoot/Public/*.ps1" -ErrorAction SilentlyContinue)
foreach ($import in $Public) {
    try { . $import.FullName }
    catch { Write-Error "Failed to import public function $($import.FullName): $_" }
}

Write-Verbose "Action1.Tools module loaded"

# Try to load saved credentials if they exist
$credPathXml  = Join-Path $script:Action1ConfigDir "credentials.xml"
$credPathJson = Join-Path $script:Action1ConfigDir "credentials.json"

if (Test-Path $credPathXml) {
    # Load DPAPI-encrypted credentials (Windows)
    try {
        $savedCreds = Import-Clixml -Path $credPathXml
        $script:Action1ClientId = $savedCreds.ClientId
        $script:Action1ClientSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($savedCreds.ClientSecret)
        )
        $script:Action1Region = $savedCreds.Region ?? 'NorthAmerica'

        # Set the base URI based on region
        if ($script:Action1Region -and $script:Action1RegionUrls.ContainsKey($script:Action1Region)) {
            $script:Action1BaseUri = $script:Action1RegionUrls[$script:Action1Region]
        }

        Write-Verbose "Loaded encrypted Action1 credentials (Region: $($script:Action1Region))"
    }
    catch {
        Write-Verbose "Could not load encrypted credentials: $_"
    }
}
elseif (Test-Path $credPathJson) {
    # Legacy plaintext JSON format
    try {
        $savedCreds = Get-Content $credPathJson -Raw | ConvertFrom-Json

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
        Write-Warning "Credentials are stored in plaintext. Run Set-Action1ApiCredentials -SaveToProfile to encrypt them."
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
    # Generic API Functions (PSAction1 compatible)
    'Get-Action1',
    'New-Action1',
    'Update-Action1',
    'Start-Action1Requery',
    'Start-Action1PackageUpload',

    # Connection & Configuration
    'Test-Action1Connection',
    'Set-Action1ApiCredentials',
    'Get-Action1ApiCredentials',
    'Set-Action1LogLevel',
    'Get-Action1LogLevel',
    'Set-Action1Interactive',
    'Get-Action1Interactive',

    # Organizations & Groups
    'Get-Action1Organization',
    'Get-Action1EndpointGroup',
    'New-Action1EndpointGroup',

    # Automations
    'Get-Action1Automation',
    'Copy-Action1Automation',

    # App Repositories
    'New-Action1AppRepo',
    'Get-Action1AppRepo',
    'Remove-Action1AppRepo',
    'Export-Action1AppRepo',
    'Deploy-Action1AppRepo',

    # App Packages
    'New-Action1AppPackage',
    'Get-Action1AppPackage',
    'Remove-Action1AppPackage',
    'Export-Action1AppPackage',
    'Deploy-Action1AppPackage',
    'Deploy-Action1AppUpdate'
)
