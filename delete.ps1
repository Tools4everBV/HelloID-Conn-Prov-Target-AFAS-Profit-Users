$config = ConvertFrom-Json $configuration
$updateOnly = $config.updateOnly
$BaseUri = $config.BaseUri
$token = $config.Token
$getConnector = "T4E_HelloID_Users"
$updateConnector = "knUser"

#Initialize default properties
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$success = $False
$auditLogs = New-Object Collections.Generic.List[PSCustomObject]

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$personId = $p.ExternalId # Profit Person number (which could be different to the Profit Employee number)

#emailadres + upn wijzigingen.
$emailaddress = $null # or "$personId@customer.nl" # Unique value based of PersonId because at the revoke action we want to clear the unique fields.
$userPrincipalName = $null # or "$personId@customer.nl" # Unique value based of PersonId because at the revoke action we want to clear the unique fields

try{
    if ($updateOnly -eq $false){
        $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($token))
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
                            "Nm" = "Deleted by HelloID Provisioning"
                            # E-mail
                           'EmAd'  = $emailaddress
                            # UPN
                            'Upn' = $userPrincipalName
                        }
                    }
                }
            }

            if(-Not($dryRun -eq $True)){  
                $body = $account | ConvertTo-Json -Depth 10
                $putUri = $BaseUri + "/connectors/" + $updateConnector
                $auditLogs.Add([PSCustomObject]@{
                    Action = "DeleteAccount"
                    Message = "Deleted account with Id $($aRef)"
                    IsError = $false
                })
                $null = Invoke-RestMethod -Method Put -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing -ErrorAction Stop

                $success = $true
            }
        }
    }else{
        $auditLogs.Add([PSCustomObject]@{
            Action = "DeleteAccount"
            Message = "Deleted account with Id $($aRef)"
            IsError = $false
        })

        $success = $true
    }
}catch{
    $auditLogs.Add([PSCustomObject]@{
        Action = "DeleteAccount"
        Message = "Error deleting account with Id $($aRef): $($_)"
        IsError = $True
    })
	Write-Verbose -Verbose "$_"
}

# Send results
$result = [PSCustomObject]@{
	Success= $success
	AccountReference= $aRef
	AuditLogs = $auditLogs
    Account = $account
}
Write-Output $result | ConvertTo-Json -Depth 10