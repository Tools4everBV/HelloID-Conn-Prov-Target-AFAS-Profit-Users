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
$auditMessage = "Profit account for person " + $p.DisplayName + " not enabled successfully";

$personId = $p.externalId;

#Change mapping here
$accountFields = [PSCustomObject]@{
    # Mutatie code
    'MtCd' = 6;
    # Omschrijving
    "Nm" = "Enabled by HelloID Provisioning";

    # Profit Windows
    "Awin" = $true;
    # Connector
    "Acon" = $true;
    # Reservekopieen via commandline
    "Abac" = $true;
    # Commandline
    "Acom" = $true;

    # Outsite
    "Site" = $true;
    # InSite
    "InSi" = $true;

    # Meewerklicentie actieveren
    "OcUs" = $false;
    # AFAS Online Portal-beheerder
    "PoMa" = $false;
    # AFAS Accept
    "AcUs" = $false;

    <#
    # Groep
    'GrId' = "groep1";
    # Groep omschrijving
    'GrDs' = "Groep omschrijving1";
    # Persoon code
    "BcCo" = $persoonCode;
    # Nieuwe gebruikerscode
    "UsIdNew" = $userId;
    # E-mail
    'EmAd'  = $emailaddress;
    # Afwijkend e-mailadres
    "XOEA" = "test1@a-mail.nl";
    # UPN
    'UPN' = $userPrincipalName;
    # Voorkeur site
    "InLn" = "1043"; # NL
    #>
}

try{
    if(-Not($dryRun -eq $True)){
        $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
        $authValue = "AfasToken $encodedToken"
        $Headers = @{ Authorization = $authValue }

        $getUri = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=PersonId&filtervalues=$personId"
        $getResponse = Invoke-RestMethod -Method Get -Uri $getUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing

        $account = [PSCustomObject]@{
            'KnUser' = @{
                'Element' = @{
                    '@UsId' = $getResponse.rows.UserId;
                    'Fields' = $accountFields
                }
            }
        }

        $body = $account | ConvertTo-Json -Depth 10
        $putUri = $BaseUri + "/connectors/" + $updateConnector
        $putResponse = Invoke-RestMethod -Method Put -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing
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