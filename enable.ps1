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
                    'MtCd' = 6;
                    # Omschrijving
                    "Nm" = "Enabled by HelloID Provisioning on $currentDate";
  
                    # Outsite
                    #"Site" = $false;
                    # InSite
                    "InSi" = $true;

                    <#
                    # Persoon code
                    "BcCo" = $getResponse.rows.nummer;
                    # Nieuwe gebruikerscode
                    "UsIdNew" = "$customerNr." + $personId;

                    # UPN
                    'Upn' = $userPrincipalName;
                    # E-mail
                    'EmAd'  = $emailaddress;

                    # Wachtwoord
                    "Pw" = "GHJKL!!!23456gfdgf" # dummy pwd, not used, but required

                    # Groep
                    'GrId' = "groep1";
                    # Groep omschrijving
                    'GrDs' = "Groep omschrijving1";

                    # Afwijkend e-mailadres
                    "XOEA" = "test1@a-mail.nl";
                    # Voorkeur site
                    "InLn" = "1043"; # NL

                    # Profit Windows
                    "Awin" = $false;
                    # Connector
                    "Acon" = $false;
                    # Reservekopieen via commandline
                    "Abac" = $false;
                    # Commandline
                    "Acom" = $false;

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