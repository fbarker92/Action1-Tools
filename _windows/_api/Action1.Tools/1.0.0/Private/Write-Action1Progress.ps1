function Write-Action1Progress {
    <#
    .SYNOPSIS
        Displays progress bar for operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Activity,
        
        [Parameter()]
        [string]$Status = "Processing",
        
        [Parameter(Mandatory)]
        [int]$PercentComplete,
        
        [Parameter()]
        [int]$Id = 0,
        
        [Parameter()]
        [int]$ParentId = -1
    )
    
    $params = @{
        Activity = $Activity
        Status = $Status
        PercentComplete = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
        Id = $Id
    }
    
    if ($ParentId -ge 0) {
        $params['ParentId'] = $ParentId
    }
    
    Write-Progress @params
}
