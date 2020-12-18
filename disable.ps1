$config = ConvertFrom-Json $configuration

$BaseUri = $config.BaseUri
$Token = $config.Token
$getConnector = "T4E_HelloID_Users"
$updateConnector = "knUser"

# Enable TLS 1.2
if ([Net.ServicePointManager]::SecurityProtocol -notmatch "Tls12") {
    [Net.ServicePointManager]::SecurityProtocol += [Net.SecurityProtocolType]::Tls12
}

#Initialize default properties
$success = $False;
$p = $person | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$auditMessage = "Profit account for person " + $p.DisplayName + " not disabled successfully";

$personId = $p.ExternalId; # Profit Employee Nummer

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
                    '@UsId' = $getResponse.rows.Gebruiker;
                    'Fields' = @{
                        # Mutatie code
                        'MtCd' = 2;
                        # Omschrijving
                        "Nm" = "Disabled by HelloID Provisioning on $currentDate";

                        # Persoon code - Only specify this if you want to update the linked person - Make sure this has a value, otherwise the link will disappear
                        # "BcCo" = $getResponse.rows.Persoonsnummer;  

                        # InSite
                        "InSi" = $false;
                    }
                }
            }
        }

        if(-Not($dryRun -eq $True)){
            $body = $account | ConvertTo-Json -Depth 10
            $putUri = $BaseUri + "/connectors/" + $updateConnector

            $putResponse = Invoke-RestMethod -Method Put -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing
        }
        $success = $True;
        $auditMessage = " $($account.knUser.Values.'@UsId') successfully";
    }
}catch{
    $errResponse = $_;
    $auditMessage = " $($account.knUser.Values.'@UsId') : ${errResponse}";
}

#build up result
$result = [PSCustomObject]@{
    Success= $success;
    AccountReference= $aRef;
    AuditDetails=$auditMessage;
    Account= $account;  
};
    
Write-Output $result | ConvertTo-Json -Depth 10;
