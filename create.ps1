$token = "<provide XML token here>"
$baseUri = "https://<Provide Environment Id here>.rest.afas.online/profitrestservices";
$getConnector = "T4E_IAM3_Persons"
$updateConnector = "knUser"
$customerNr = "<Provide Environment Id here>"

# Enable TLS 1.2
if ([Net.ServicePointManager]::SecurityProtocol -notmatch "Tls12") {
    [Net.ServicePointManager]::SecurityProtocol += [Net.SecurityProtocolType]::Tls12
}

#Initialize default properties
$success = $False;
$p = $person | ConvertFrom-Json;
$auditMessage = "Profit account for person " + $p.DisplayName + " not created successfully";

$personId = $p.custom.customField1; # Profit Employee Nummer
$emailaddress = $p.Accounts.MicrosoftAzureAD.userPrincipalName;
$userPrincipalName = $p.Accounts.MicrosoftAzureAD.userPrincipalName;

try{
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }

    $getUri = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=Nummer&filtervalues=$personId"
    $getResponse = Invoke-RestMethod -Method Get -Uri $getUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing

    #Change mapping here
    $account = [PSCustomObject]@{
        'KnUser' = @{
            'Element' = @{
                # Gebruiker
                '@UsId' = "$customerNr." + $personId;
                'Fields' = @{
                    # Mutatie code
                    'MtCd' = 1;
                    # Omschrijving
                    "Nm" = "Created by HelloID Provisioning";

                    # Persoon code
                    "BcCo" = $getResponse.rows.nummer;
                    # Nieuwe gebruikerscode
                    "UsIdNew" = $userId;

                    # UPN
                    'UPN' = $userPrincipalName;
                    # E-mail
                    'EmAd'  = $emailaddress;
                    # Outsite
                    "Site" = $true;
                    # InSite
                    "InSi" = $true;

                    <#
                    # Wachtwoord
                    "Pw" = "Tools4ever!"


                    # Groep
                    'GrId' = "groep1";
                    # Groep omschrijving
                    'GrDs' = "Groep omschrijving1";

                    # Profit Windows
                    "Awin" = $true;
                    # Connector
                    "Acon" = $true;
                    # Reservekopieen via commandline
                    "Abac" = $true;
                    # Commandline
                    "Acom" = $true;

                    # Afwijkend e-mailadres
                    "XOEA" = "test1@a-mail.nl";
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

        $postResponse = Invoke-RestMethod -Method Post -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing
        $aRef = $($account.knUser.Values.'@UsId')
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
        if($errResponse -like "*Aan de gekozen persoon is al een gebruiker gekoppeld*"){
            $success = $True;
            $auditMessage = "already linked to this person. Account not";
        }else{
            $auditMessage = "  = ${errResponse}";
        }
    }else {
        $auditMessage = "  = General error";
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