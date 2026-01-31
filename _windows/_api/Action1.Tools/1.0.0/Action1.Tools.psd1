@{
    RootModule = 'Action1.Tools.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'Fergus Barker'
    CompanyName = 'SpringWest IT Ltd'
    Copyright = '(c) 2026. All rights reserved.'
    Description = 'PowerShell module for deploying and managing Action1 applications, automations, and software repositories'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        # Connection & Configuration
        'Test-Action1Connection',
        'Set-Action1ApiCredentials',
        'Get-Action1ApiCredentials',
        'Set-Action1LogLevel',
        'Get-Action1LogLevel',

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

    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @('Action1', 'Deployment', 'RMM', 'Automation', 'SoftwareRepository')
            LicenseUri = ''
            ProjectUri = ''
            IconUri = ''
            ReleaseNotes = @'
v1.0.0 - Initial release
- App repository and package management
- Automation copy between organizations
- Software deployment functions
- Export functionality for packages and repositories
'@
        }
    }
}
