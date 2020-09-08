$token = "<provide XML token here>"
$baseUri = "https://<Provide Environment Id here>.rest.afas.online/profitrestservices";
$getPersonConnector = "T4E_IAM3_Persons"
$getUserConnector = "T4E_IAM3_Users"
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

$personId = $p.custom.nummer; # Profit Employee Nummer
$emailaddress = $p.Accounts.MicrosoftAzureAD.mail;
$userPrincipalName = $p.Accounts.MicrosoftAzureAD.userPrincipalName;
$userId = $customerNr + "." + $p.Name.NickName
if(![string]::IsNullOrEmpty($p.Name.FamilyNamePrefix)){$p.Name.FamilyNamePrefix.Split(" ") | foreach {$userId = $userId + $_[0]}}
$userId = $userId + ($p.Name.FamilyName)[0]

$currentDate = (Get-Date).ToString("dd/MM/yyyy hh:mm:ss")

try{
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }

    $getUserUri = $BaseUri + "/connectors/" + $getUserConnector + "?filterfieldids=PersonId&filtervalues=$personId"
    $getUserResponse = Invoke-RestMethod -Method Get -Uri $getUserUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing -ErrorAction Stop

    if($getUserResponse.rows.Count -eq 1){
        # Account already linked to this person. Updating account

        # If User ID doesn't match naming convention, update this
        if($getUserResponse.rows.UserId -ne $userId){
            $account = [PSCustomObject]@{
                'KnUser' = @{
                    'Element' = @{
                        '@UsId' = $getUserResponse.rows.UserId;
                        'Fields' = @{
                            # Mutatie code
                            'MtCd' = 4;
                            # Omschrijving
                            "Nm" = "Updated User ID by HelloID Provisioning on $currentDate";

                             # Nieuwe gebruikerscode
                            "UsIdNew" = $userId;
                        }
                    }
                }
            }

            if(-Not($dryRun -eq $True)){
                $body = $account | ConvertTo-Json -Depth 10
                $putUri = $BaseUri + "/connectors/" + $updateConnector

                $putResponse = Invoke-RestMethod -Method Put -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing -ErrorAction Stop
            }
        }

        $account = [PSCustomObject]@{
            'KnUser' = @{
                'Element' = @{
                    '@UsId' = $userId;
                    'Fields' = @{
                        # Mutatie code
                        'MtCd' = 1;
                        # Omschrijving
                        "Nm" = "Updated by HelloID Provisioning on $currentDate";

                        # E-mail
                        'EmAd'  = $emailaddress;
                        # UPN
                        'Upn' = $userPrincipalName;

                        # Outsite
                        "Site" = $false;
                        # InSite
                        "InSi" = $true;

                        <#
                        # Persoon code
                        "BcCo" = $getResponse.rows.nummer;

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

            $putResponse = Invoke-RestMethod -Method Put -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing -ErrorAction Stop
        }
            
        $aRef = $($account.knUser.Values.'@UsId')
        $success = $True;
        $auditMessage = " already linked to this person. Account updated instead of"; 
    }else{
        # Creating account
        $getPersonUri = $BaseUri + "/connectors/" + $getPersonConnector + "?filterfieldids=Nummer&filtervalues=$personId"
        $getPersonResponse = Invoke-RestMethod -Method Get -Uri $getPersonUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing -ErrorAction Stop

        #Change mapping here
        $account = [PSCustomObject]@{
            'KnUser' = @{
                'Element' = @{
                    # Gebruiker
                    '@UsId' = $userId;
                    'Fields' = @{
                        # Mutatie code
                        'MtCd' = 1;
                        # Omschrijving
                        "Nm" = "Created by HelloID Provisioning on $currentDate";

                        # Persoon code
                        "BcCo" = $getPersonResponse.rows.nummer;
                        # Nieuwe gebruikerscode
                        "UsIdNew" = $userId;

                        # E-mail
                        'EmAd'  = $emailaddress;
                        # UPN
                        'Upn' = $userPrincipalName;

                        # Profit Windows
                        "Awin" = $false;
                        # Connector
                        "Acon" = $false;
                        # Reservekopieen via commandline
                        "Abac" = $false;
                        # Commandline
                        "Acom" = $false;

                        # Outsite
                        "Site" = $false;
                        # InSite
                        "InSi" = $true;

                        # Wachtwoord
                        "Pw" = "GHJKL!!!23456gfdgf" # dummy pwd, not used, but required

                        <#
                        # Groep
                        'GrId' = "groep1";
                        # Groep omschrijving
                        'GrDs' = "Groep omschrijving1";

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
            $postUri = $BaseUri + "/connectors/" + $updateConnector

            $postResponse = Invoke-RestMethod -Method Post -Uri $postUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing -ErrorAction Stop
        }
            
        $aRef = $($account.knUser.Values.'@UsId')
        $success = $True;
        $auditMessage = " successfully";         
    }
}catch{
    if(-Not($_.Exception.Response -eq $null)){
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $errResponse = $reader.ReadToEnd();
        if($errResponse -like "*Aan de gekozen persoon is al een gebruiker gekoppeld*"){
            $aRef = $($account.knUser.Values.'@UsId')            
            $success = $True;
            $auditMessage = " already linked to this person. Account not";
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