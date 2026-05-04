function Get-DigitalSignatureMetadata {
    <#
    .SYNOPSIS
        Extracts metadata from the digital signature/code signing certificate of an installer.

    .DESCRIPTION
        Parses the Authenticode signature to extract publisher information from the
        signing certificate's subject field.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Write-Action1Log "Attempting to extract digital signature metadata from: $Path" -Level DEBUG

    $result = @{
        Success = $false
        Publisher = $null
        Subject = $null
        Issuer = $null
        SignatureStatus = $null
        Source = "Digital Signature"
    }

    try {
        $signature = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop

        if ($signature.Status -ne 'NotSigned' -and $null -ne $signature.SignerCertificate) {
            $result.SignatureStatus = $signature.Status.ToString()
            $result.Subject = $signature.SignerCertificate.Subject
            $result.Issuer = $signature.SignerCertificate.Issuer

            # Parse the subject to extract organization/company name
            # Subject format: CN=Company Name, O=Organization, L=City, S=State, C=Country
            $subject = $signature.SignerCertificate.Subject

            # Try to extract O (Organization) first, then CN (Common Name)
            if ($subject -match 'O=([^,]+)') {
                $result.Publisher = $matches[1].Trim().Trim('"')
            }
            elseif ($subject -match 'CN=([^,]+)') {
                $result.Publisher = $matches[1].Trim().Trim('"')
            }

            $result.Success = ($null -ne $result.Publisher)

            Write-Action1Log "Digital signature metadata extracted" -Level DEBUG -Data @{
                Publisher = $result.Publisher
                Status = $result.SignatureStatus
                Subject = $result.Subject
            }
        }
        else {
            Write-Action1Log "File is not signed or signature is invalid" -Level DEBUG
        }
    }
    catch {
        Write-Action1Log "Failed to extract digital signature metadata" -Level DEBUG -ErrorRecord $_
    }

    return $result
}
