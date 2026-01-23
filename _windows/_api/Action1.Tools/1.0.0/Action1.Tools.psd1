@{
    RootModule = 'Action1.Tools.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'Fergus Barker'
    CompanyName = 'SpringWest IT Ltd'
    Copyright = '(c) 2026. All rights reserved.'
    Description = 'PowerShell module for deploying and managing Action1 applications'
    PowerShellVersion = '7.0'
    
    FunctionsToExport = @(
        'Deploy-Action1App',
        'Deploy-Action1AppUpdate',
        'New-Action1AppRepo',
        'New-Action1AppPackage',
        'Get-Action1App',
        'Remove-Action1App',
        'Test-Action1Connection',
        'Set-Action1ApiCredentials',
        'Set-Action1LogLevel',
        'Get-Action1LogLevel'
    )
    
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    
    PrivateData = @{
        PSData = @{
            Tags = @('Action1', 'Deployment', 'RMM', 'Automation')
            LicenseUri = ''
            ProjectUri = ''
            IconUri = ''
            ReleaseNotes = 'Initial release of Action1 App Deployment module'
        }
    }
}
