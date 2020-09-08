$token = "<provide XML token here>"
$baseUri = "https://<Provide Environment Id here>.rest.afas.online/profitrestservices";
$getConnector = "T4E_IAM3_Users"
$updateConnector = "KnUser"

# Enable TLS 1.2
if ([Net.ServicePointManager]::SecurityProtocol -notmatch "Tls12") {
    [Net.ServicePointManager]::SecurityProtocol += [Net.SecurityProtocolType]::Tls12
}

#Initialize default properties
$success = $False;
$p = $person | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$auditMessage = "Profit account for person " + $p.DisplayName + " not deleted successfully";

$personId = $p.custom.Nummer; # Profit Employee Nummer

$currentDate = (Get-Date).ToString("dd/MM/yyyy hh:mm:ss")

try{
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }

    $getUri = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=PersonId&filtervalues=$personId"
    $getResponse = Invoke-RestMethod -Method Get -Uri $getUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing

    # Change mapping here
    $account = [PSCustomObject]@{
        'KnUser' = @{
            'Element' = @{
                '@UsId' = $getResponse.rows.UserId;
                'Fields' = @{
                    # Mutatie code
                    'MtCd' = 2;
                    # Omschrijving
                    "Nm" = "Deleted by HelloID Provisioning on $currentDate";
                }
            }
        }
    }

    if(-Not($dryRun -eq $True)){
        $deleteUri = $BaseUri + "/connectors/" + $updateConnector + "/KnUser/@UsId,MtCd,GrId,GrDs,BcCo,UsIdNew,Nm,Awin,Acon,Abac,Acom,Site,EmAd,XOEA,InSi,Upn,InLn,OcUs,PoMa,AcUs/$($account.knUser.Values.'@UsId'),,,,,$($account.knUser.Values.Fields.MtCd),$($account.knUser.Values.Fields.Nm),false,false,false,false,false,,,false,,,false,false,false"
        $deleteResponse = Invoke-RestMethod -Method DELETE -Uri $deleteUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing
    }
    $success = $True;
    $auditMessage = " successfully"; 
}catch{
    if(-Not($_.Exception.Response -eq $null)){
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $errResponse = $reader.ReadToEnd();
        $auditMessage = " : ${errResponse}";
    }else {
        $auditMessage = " : General error";
    } 
}

#build up result
$result = [PSCustomObject]@{
    Success= $success;
    AccountReference= $aRef;
    AuditDetails=$auditMessage;
    Account= $account;
};
    
Write-Output $result | ConvertTo-Json -Depth 10;