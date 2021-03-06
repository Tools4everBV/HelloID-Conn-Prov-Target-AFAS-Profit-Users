$config = ConvertFrom-Json $configuration

$BaseUri = $config.BaseUri
$Token = $config.Token
$getConnector = "T4E_HelloID_Users"
$updateConnector = "knUser"

#Initialize default properties
$p = $person | ConvertFrom-Json;
$m = $manager | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$mRef = $managerAccountReference | ConvertFrom-Json;
$success = $False;
$auditLogs = New-Object Collections.Generic.List[PSCustomObject];

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

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
                        "Nm" = "Deleted by HelloID Provisioning";
                    }
                }
            }
        }

        if(-Not($dryRun -eq $True)){
            $deleteUri = $BaseUri + "/connectors/" + $updateConnector + "/KnUser/@UsId,MtCd,GrId,GrDs,BcCo,UsIdNew,Nm,Awin,Acon,Abac,Acom,Site,EmAd,XOEA,InSi,Upn,InLn,OcUs,PoMa,AcUs/$($account.knUser.Values.'@UsId'),,,,,$($account.knUser.Values.Fields.MtCd),$($account.knUser.Values.Fields.Nm),false,false,false,false,false,,,false,,,false,false,false"
            $deleteResponse = Invoke-RestMethod -Method DELETE -Uri $deleteUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing
        }

        $auditLogs.Add([PSCustomObject]@{
            Action = "DeleteAccount"
            Message = "Deleted account with Id $($aRef)"
            IsError = $false;
        });

        $success = $true;    
    }
}catch{
    $auditLogs.Add([PSCustomObject]@{
        Action = "DeleteAccount"
        Message = "Error deleting account with Id $($aRef): $($_)"
        IsError = $True
    });
	Write-Error $_;
}

# Send results
$result = [PSCustomObject]@{
	Success= $success;
	AccountReference= $aRef;
	AuditLogs = $auditLogs;
    Account = $account;
};
Write-Output $result | ConvertTo-Json -Depth 10;