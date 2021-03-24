$config = ConvertFrom-Json $configuration

$BaseUri = $config.BaseUri
$Token = $config.Token
$getConnector = "T4E_HelloID_Users"
$updateConnector = "knUser"

#Initialize default properties
$p = $person | ConvertFrom-Json;
$pp = $previousPerson | ConvertFrom-Json
$pd = $personDifferences | ConvertFrom-Json
$m = $manager | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$mRef = $managerAccountReference | ConvertFrom-Json;
$success = $False;
$auditLogs = New-Object Collections.Generic.List[PSCustomObject];

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$personId = $p.ExternalId; # Profit Employee Nummer
$emailaddress = $p.Accounts.AzureADSchoulens.userPrincipalName + "1";
$userPrincipalName = $p.Accounts.AzureADSchoulens.userPrincipalName + "1";

$currentDate = (Get-Date).ToString("dd/MM/yyyy hh:mm:ss")

try{
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }

    $getUri = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=Persoonsnummer&filtervalues=$personId&operatortypes=1"
    $getResponse = Invoke-RestMethod -Method Get -Uri $getUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing

    if($getResponse.rows.Count -eq 1 -and (![string]::IsNullOrEmpty($getResponse.rows.Gebruiker))){
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

        if(-Not($dryRun -eq $True)){
            $body = $account | ConvertTo-Json -Depth 10
            $putUri = $BaseUri + "/connectors/" + $updateConnector

            $putResponse = Invoke-RestMethod -Method Put -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing
        }

        $auditLogs.Add([PSCustomObject]@{
            Action = "UpdateAccount"
            Message = "Updated fields of account  with Id $($aRef)"
            IsError = $false;
        });

        $success = $true;  
    }
}catch{
    $auditLogs.Add([PSCustomObject]@{
        Action = "UpdateAccount"
        Message = "Error updating fields of account with Id $($aRef): $($_)"
        IsError = $True
    });
	Write-Error $_;
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