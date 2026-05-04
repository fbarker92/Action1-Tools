function Invoke-Action1DirectUpload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [string]$Endpoint,
        
        [Parameter()]
        [hashtable]$AdditionalData
    )
    
    $fileInfo = Get-Item $FilePath
    $fileName = $fileInfo.Name
    $fileSize = $fileInfo.Length
    
    Write-Action1Progress -Activity "Uploading $fileName" -Status "Reading file..." -PercentComplete 0 -Id 1
    
    try {
        $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
        Write-Action1Log "File read into memory: $(ConvertTo-FileSize -Bytes $fileBytes.Length)" -Level DEBUG
        
        Write-Action1Progress -Activity "Uploading $fileName" -Status "Encoding..." -PercentComplete 25 -Id 1
        
        $base64Content = [Convert]::ToBase64String($fileBytes)
        Write-Action1Log "File encoded to base64: $($base64Content.Length) characters" -Level DEBUG
        
        Write-Action1Progress -Activity "Uploading $fileName" -Status "Uploading to Action1..." -PercentComplete 50 -Id 1
        
        $uploadData = @{
            fileName = $fileName
            fileData = $base64Content
        }
        
        if ($AdditionalData) {
            foreach ($key in $AdditionalData.Keys) {
                $uploadData[$key] = $AdditionalData[$key]
            }
        }
        
        $response = Invoke-Action1ApiRequest -Endpoint $Endpoint -Method POST -Body $uploadData
        
        Write-Action1Progress -Activity "Uploading $fileName" -Status "Complete" -PercentComplete 100 -Id 1
        Start-Sleep -Milliseconds 500
        Write-Progress -Activity "Uploading $fileName" -Id 1 -Completed
        
        Write-Action1Log "File uploaded successfully" -Level INFO
        return $response
    }
    catch {
        Write-Progress -Activity "Uploading $fileName" -Id 1 -Completed
        Write-Action1Log "Direct upload failed" -Level ERROR -ErrorRecord $_
        throw
    }
}
