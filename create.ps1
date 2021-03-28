$config = ConvertFrom-Json $configuration

$BaseUri = $config.BaseUri
$Token = $config.Token
$RelationNumber = $config.RelationNumber
$updateUserId = $config.updateUserId
$getConnector = "T4E_HelloID_Users"
$updateConnector = "knUser"

#Initialize default properties
$p = $person | ConvertFrom-Json;
$m = $manager | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$mRef = $managerAccountReference | ConvertFrom-Json;
$success = $False;
$auditLogs = New-Object Collections.Generic.List[PSCustomObject];

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$personId = $p.ExternalId; # Profit Employee Nummer
$emailaddress = $p.Accounts.AzureADSchoulens.userPrincipalName  + "1";
$userPrincipalName = $p.Accounts.AzureADSchoulens.userPrincipalName + "1";
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
        
        if($updateUserId -eq $true){
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
        }

        # Retrieve current account data for properties to be updated
        $previousAccount = [PSCustomObject]@{
            'KnUser' = @{
                'Element' = @{
                    '@UsId' = $getResponse.rows.Gebruiker;
                    'Fields' = @{
                        # E-mail
                        'EmAd'  = $getResponse.rows.Email_werk_gebruiker;
                        # UPN
                        'Upn' = $getResponse.rows.UPN;
                    }
                }
            }
        }
        
        # Map the properties to update
        $account = [PSCustomObject]@{
            'KnUser' = @{
                'Element' = @{
                    '@UsId' = $getResponse.rows.Gebruiker;
                    'Fields' = @{
                        # Mutatie code
                        'MtCd' = 1;
                        # Omschrijving
                        "Nm" = "Updated by HelloID Provisioning on $currentDate";
                    }
                }
            }
        }

        # If '$userPrincipalName' does not match current 'UPN', add 'UPN' to update body. AFAS will throw an error when trying to update this with the same value
        if($getResponse.rows.UPN -ne $userPrincipalName){
            # vulling UPN afstemmen met AFAS beheer
            # UPN
            $account.'KnUser'.'Element'.'Fields' += @{'Upn' = $userPrincipalName}
            Write-Verbose -Verbose "Updating UPN '$($getResponse.rows.UPN)' with new value '$userPrincipalName'"
        }

        # If '$emailAdddres' does not match current 'EmAd', add 'EmAd' to update body. AFAS will throw an error when trying to update this with the same value
        if($getResponse.rows.Email_werk_gebruiker -ne $emailaddress){
            # E-mail
            $account.'KnUser'.'Element'.'Fields' += @{'EmAd' = $emailaddress}
            Write-Verbose -Verbose "Updating BusinessEmailAddress '$($getResponse.rows.Email_werk_gebruiker)' with new value '$emailaddress'"
        }                  

        $aRef = $($account.knUser.Values.'@UsId')

        if(-Not($dryRun -eq $True)){
            $body = $account | ConvertTo-Json -Depth 10
            $putUri = $BaseUri + "/connectors/" + $updateConnector

            $putResponse = Invoke-RestMethod -Method Put -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing -ErrorAction Stop
        }
        
        $auditLogs.Add([PSCustomObject]@{
            Action = "CreateAccount"
            Message = "Correlated to and updated fields of account with id $aRef"
            IsError = $false;
        });

        $success = $true;          
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

        $aRef = $($account.knUser.Values.'@UsId')

        if(-Not($dryRun -eq $True)){
            $body = $account | ConvertTo-Json -Depth 10
            $postUri = $BaseUri + "/connectors/" + $updateConnector

            $postResponse = Invoke-RestMethod -Method Post -Uri $postUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing -ErrorAction Stop
        }
        
        $auditLogs.Add([PSCustomObject]@{
            Action = "CreateAccount"
            Message = "Created account with Id $($aRef)"
            IsError = $false;
        });

        $success = $true;          
    }
}catch{
    $errResponse = $_;
    if($errResponse -like "*Aan de gekozen persoon is al een gebruiker gekoppeld*"){
        $auditLogs.Add([PSCustomObject]@{
            Action = "CreateAccount"
            Message = "Correlated to account with id $aRef";
            IsError = $false;
        });        

        $success = $true; 
    }else{
        $auditLogs.Add([PSCustomObject]@{
            Action = "CreateAccount"
            Message = "Error creating account with Id $($aRef): $($_)"
            IsError = $True
        });
        Write-Error $_;
    }
}

# Send results
$result = [PSCustomObject]@{
	Success= $success;
	AccountReference= $aRef;
	AuditLogs = $auditLogs;
    Account = $account;
    PreviousAccount = $previousAccount;    

    # Optionally return data for use in other systems
    ExportData = [PSCustomObject]@{
        UserId                  = $($account.knUser.Values.'@UsId')
        UPN                     = $($account.KnUser.Element.Fields.UPN)
        BusinessEmailAddress    = $($account.KnUser.Element.Fields.EmAd)
    };    
};
Write-Output $result | ConvertTo-Json -Depth 10;
