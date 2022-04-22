$config = ConvertFrom-Json $configuration

$BaseUri = $config.BaseUri
$Token = $config.Token
$getConnector = "T4E_HelloID_Users"
$updateConnector = "knUser"

#Initialize default properties
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[object]]::new()

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$personId = $p.ExternalId # Profit Person number (which could be different to the Profit Employee number)

$currentDate = (Get-Date).ToString("dd/MM/yyyy hh:mm:ss")

try{
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }
    $getUri = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=Persoonsnummer&filtervalues=$personId&operatortypes=1"

    $getResponse = Invoke-RestMethod -Method Get -Uri $getUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing

    if($getResponse.rows.Count -eq 1 -and (![string]::IsNullOrEmpty($getResponse.rows.Gebruiker))){

        # Change mapping here
        $account = [PSCustomObject]@{
            'KnUser' = @{
                'Element' = @{
                    '@UsId' = $getResponse.rows.Gebruiker
                    'Fields' = @{
                        # Mutatie code
                        'MtCd' = 2
                        # Omschrijving
                        "Nm" = "Disabled by HelloID Provisioning on $currentDate"

                        # Persoon code - Only specify this if you want to update the linked person - Make sure this has a value, otherwise the link will disappear
                        # "BcCo" = $getResponse.rows.Persoonsnummer

                        # InSite
                        "InSi" = $false
                    }
                }
            }
        }


        $body = $account | ConvertTo-Json -Depth 10
        $putUri = $BaseUri + "/connectors/" + $updateConnector
        if(-Not($dryRun -eq $True)){
            $putResponse = Invoke-RestMethod -Method Put -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing
        } else {
            Write-Verbose -Verbose $putUri
            Write-Verbose -Verbose $body
        }

        $auditLogs.Add([PSCustomObject]@{
            Action = "DisableAccount"
            Message = "Disabled account with Id $($aRef)"
            IsError = $false
        })

        $success = $true
    }
}catch{
    $auditLogs.Add([PSCustomObject]@{
        Action = "DisableAccount"
        Message = "Error disabling account with Id $($aRef): $_)"
        IsError = $true
    })

}

# Send results
$result = [PSCustomObject]@{
	Success = $success
	AccountReference = $aRef
	AuditLogs = $auditLogs
    Account = $account
}

Write-Output $result | ConvertTo-Json -Depth 10