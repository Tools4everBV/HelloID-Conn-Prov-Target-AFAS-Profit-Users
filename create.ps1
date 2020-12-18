$config = ConvertFrom-Json $configuration

$BaseUri = $config.BaseUri
$Token = $config.Token
$RelationNumber = $config.RelationNumber
$getConnector = "T4E_HelloID_Users"
$updateConnector = "knUser"

# Enable TLS 1.2
if ([Net.ServicePointManager]::SecurityProtocol -notmatch "Tls12") {
    [Net.ServicePointManager]::SecurityProtocol += [Net.SecurityProtocolType]::Tls12
}

#Initialize default properties
$success = $False;
$p = $person | ConvertFrom-Json;
$auditMessage = "Profit account for person " + $p.DisplayName + " not created successfully";

$personId = $p.ExternalId; # Profit Employee Nummer
$emailaddress = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName;
$userPrincipalName = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName;
$userId = $RelationNumber + "." + $p.Custom.employeeNumber;

$currentDate = (Get-Date).ToString("dd/MM/yyyy hh:mm:ss")

try{
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }

    $getUri = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=Persoonsnummer&filtervalues=$personId&operatortypes=1"
    $getResponse = Invoke-RestMethod -Method Get -Uri $getUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing -ErrorAction Stop

    if($getResponse.rows.Count -eq 1 -and (![string]::IsNullOrEmpty($getResponse.rows.Gebruiker))){
        # Account already linked to this person. Updating account

        # If User ID doesn't match naming convention, update this
        if($getResponse.rows.Gebruiker -ne $userId){
            $account = [PSCustomObject]@{
                'KnUser' = @{
                    'Element' = @{
                        '@UsId' = $getResponse.rows.Gebruiker;
                        'Fields' = @{
                            # Mutatie code
                            'MtCd' = 4;
                            # Omschrijving
                            "Nm" = "Updated User ID by HelloID Provisioning on $currentDate";

                            # Persoon code - Only specify this if you want to update the linked person - Make sure this has a value, otherwise the link will disappear
                            # "BcCo" = $getResponse.rows.Persoonsnummer;  

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
                Write-Verbose -Verbose "UserId [$($getResponse.rows.Gebruiker)] updated to [$userId]"
            }
        }

        # Update AFAS account
        $account = [PSCustomObject]@{
            'KnUser' = @{
                'Element' = @{
                    '@UsId' = $userId;
                    'Fields' = @{
                        # Mutatie code
                        'MtCd' = 1;
                        # Omschrijving
                        "Nm" = "Updated by HelloID Provisioning on $currentDate";

                        # Persoon code - Only specify this if you want to update the linked person - Make sure this has a value, otherwise the link will disappear
                        # "BcCo" = $getResponse.rows.Persoonsnummer;  

                        # E-mail
                        'EmAd'  = $emailaddress;
                        # vulling UPN afstemmen met AFAS beheer
                        # UPN
                        'Upn' = $userPrincipalName;

                        # # Outsite
                        "Site" = $false;
                        # # InSite
                        "InSi" = $true; 

                        <#
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
        $auditMessage = " $($account.knUser.Values.'@UsId') already exists for this person. Account updated instead of"; 
    }else{
        # Account doesn't exist this person. Creating account

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
                        "BcCo" = $getResponse.rows.Persoonsnummer;
                        # Nieuwe gebruikerscode
                        "UsIdNew" = $userId;

                        # E-mail
                        'EmAd'  = $emailaddress;
                        # UPN
                        # 'Upn' = $userPrincipalName;

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

                        # Meewerklicentie actieveren
                        "OcUs" = $false;
                        # AFAS Online Portal-beheerder
                        "PoMa" = $false;
                        # AFAS Accept
                        "AcUs" = $false;

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
        $auditMessage = " $($account.knUser.Values.'@UsId') successfully";         
    }
}catch{
    $errResponse = $_;
    if($errResponse -like "*Aan de gekozen persoon is al een gebruiker gekoppeld*"){
        $aRef = $($account.knUser.Values.'@UsId')            
        $success = $True;
        $auditMessage = " $($account.knUser.Values.'@UsId') already exists for this person. Skipped action and treated like";
    }else{
        $auditMessage = " $($account.knUser.Values.'@UsId') : ${errResponse}";
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
