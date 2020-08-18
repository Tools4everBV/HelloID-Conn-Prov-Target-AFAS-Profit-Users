$token = "<provide XML token here>"
$baseUri = "https://<Provide Environment Id here>.rest.afas.online/profitrestservices";
$updateConnector = "knUser"
$customerNr = "<Provide Environment Id here>"

# Enable TLS 1.2
if ([Net.ServicePointManager]::SecurityProtocol -notmatch "Tls12") {
    [Net.ServicePointManager]::SecurityProtocol += [Net.SecurityProtocolType]::Tls12
}

#Initialize default properties
$success = $False;
$p = $person | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$auditMessage = "Profit account for person " + $p.DisplayName + " not created successfully";

$personId = $p.externalId;
$userId = "$customerNr." + $personId;
$emailaddress = $p.Accounts.MicrosoftAzureAD.mail;
$userPrincipalName = $p.Accounts.MicrosoftAzureAD.userPrincipalName;

#Change mapping here
$account = [PSCustomObject]@{
    'KnUser' = @{
        'Element' = @{
            # Gebruiker
            '@UsId' = $userId;
            'Fields' = @{

                # Persoon code
                "BcCo" = $personId;
                # Nieuwe gebruikerscode
                "UsIdNew" = $userId;
                # Omschrijving
                "Nm" = "Created by HelloID Provisioning";

                <#
                # Groep
                'GrId' = "groep1";
                # Groep omschrijving
                'GrDs' = "Groep omschrijving1";
                #>

                <#
                # Profit Windows
                "Awin" = $true;
                # Connector
                "Acon" = $true;
                # Reservekopieen via commandline
                "Abac" = $true;
                # Commandline
                "Acom" = $true;
                #>

                # UPN
                'UPN' = $userPrincipalName;
                # E-mail
                'EmAd'  = $emailaddress;
                # Outsite
                "Site" = $true;
                # InSite
                "InSi" = $true;

               <#
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

try{
    if(-Not($dryRun -eq $True)){
        $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
        $authValue = "AfasToken $encodedToken"
        $Headers = @{ Authorization = $authValue }

        $uri = $BaseUri + "/connectors/" + $updateConnector
        $body = $account | ConvertTo-Json -Depth 10
        $Response = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing
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
        $auditMessage = "  = ${errResponse}";
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