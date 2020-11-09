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
$auditMessage = "Profit account for person " + $p.DisplayName + " not enabled successfully";

$personId = $p.ExternalId; # Profit Employee Nummer
$emailaddress = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName;
$userPrincipalName = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName;

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
                    'MtCd' = 1;
                    # Omschrijving
                    "Nm" = "Updated by HelloID Provisioning on $currentDate";

                    # Persoon code
                    "BcCo" = $getResponse.rows.Persoonsnummer;

                    # E-mail
                    'EmAd'  = $emailaddress;
                    # UPN
                    'Upn' = $userPrincipalName;

                    <#
                    # Wachtwoord
                    "Pw" = "GHJKL!!!23456gfdgf" # dummy pwd, not used, but required
                    
                    # Outsite
                    "Site" = $false;
                    # InSite
                    "InSi" = $true;
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
