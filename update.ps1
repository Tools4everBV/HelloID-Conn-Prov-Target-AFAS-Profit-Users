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
$auditMessage = "Profit account for person " + $p.DisplayName + " not updated successfully";

$personId = $p.custom.customField1; # Profit Employee Nummer
$emailaddress = $p.Accounts.MicrosoftAzureAD.userPrincipalName;
$userPrincipalName = $p.Accounts.MicrosoftAzureAD.userPrincipalName;

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
                    'MtCd' = 1;
                    # Omschrijving
                    "Nm" = "Updated by HelloID Provisioning";

                    # E-mail
                    'EmAd'  = $emailaddress;
                    # UPN
                    'UPN' = $userPrincipalName;

                    <#
                    # Groep
                    'GrId' = "groep1";
                    # Groep omschrijving
                    'GrDs' = "Groep omschrijving1";
                    # Persoon code
                    "BcCo" = $persoonCode;
                    # Nieuwe gebruikerscode
                    "UsIdNew" = $userId;
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
                    # Afwijkend e-mailadres
                    "XOEA" = "test1@a-mail.nl";
                    # InSite
                    "InSi" = $true;
                    # Voorkeur site
                    "InLn" = "1043"; # NL
                    # Meewerklicentie actieveren
                    "OcUs" = $false;
                    # AFAS Online Portal-beheerder
                    "PoMa" = $false;
                    # AFAS Accept
                    "AcUs" = $false;
                    #>
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