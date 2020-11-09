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
$auditMessage = "Profit account for person " + $p.DisplayName + " not deleted successfully";

$personId = $p.ExternalId; # Profit Employee Nummer
Write-Verbose -Verbose $personId

$currentDate = (Get-Date).ToString("dd/MM/yyyy hh:mm:ss")

try{
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }

    $getUri = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=Persoonsnummer&filtervalues=$personId"
    $getResponse = Invoke-RestMethod -Method Get -Uri $getUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing

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
    $success = $True;
    $auditMessage = " $($account.knUser.Values.'@UsId') successfully"; 
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