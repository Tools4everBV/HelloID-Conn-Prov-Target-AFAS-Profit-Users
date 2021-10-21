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

$filterfieldid = "Gebruiker"
$filtervalue = $aRef.Gebruiker; # Has to match the AFAS value of the specified filter field ($filterfieldid)

$currentDate = (Get-Date).ToString("dd/MM/yyyy hh:mm:ss")

try{
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }
    $getUri = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=$filterfieldid&filtervalues=$filtervalue&operatortypes=1"
    $getResponse = Invoke-RestMethod -Method Get -Uri $getUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing

    if($getResponse.rows.Count -eq 1 -and (![string]::IsNullOrEmpty($getResponse.rows.Gebruiker))){
        # Retrieve current account data for properties to be updated
        $previousAccount = [PSCustomObject]@{
            'KnUser' = @{
                'Element' = @{
                    '@UsId' = $getResponse.rows.Gebruiker;
                    'Fields' = @{
                        # InSite
                        'InSi' = $getResponse.rows.InSite;
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
                        'MtCd' = 6;
                        # Omschrijving
                        "Nm" = "Enabled by HelloID Provisioning on $currentDate";

                        # Persoon code - Only specify this if you want to update the linked person - Make sure this has a value, otherwise the link will disappear
                        # "BcCo" = $getResponse.rows.Persoonsnummer;  

                        # InSite
                        "InSi" = $true;
                    }
                }
            }
        }      

        # Set aRef object for use in futher actions
        $aRef = [PSCustomObject]@{
            Gebruiker = $($account.knUser.Values.'@UsId')
        }  

        if(-Not($dryRun -eq $True)){
            $body = $account | ConvertTo-Json -Depth 10
            $putUri = $BaseUri + "/connectors/" + $updateConnector

            $putResponse = Invoke-RestMethod -Method Put -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing -ErrorAction Stop
        }
        
        $auditLogs.Add([PSCustomObject]@{
            Action = "EnableAccount"
            Message = "Enabled account with Id $($aRef.Gebruiker)"
            IsError = $false;
        });

        $success = $true;          
    }
    else {
        $auditLogs.Add([PSCustomObject]@{
            Action = "DeleteAccount"
            Message = "No profit user found for person $filtervalue";
            IsError = $false;
        });        

        $success = $true;         
        Write-Warning "No profit user found for person $filtervalue";
    }        
}catch{
    $auditLogs.Add([PSCustomObject]@{
        Action = "EnableAccount"
        Message = "Error enabling account with Id $($aRef.Gebruiker): $($_)"
        IsError = $True
    });
    Write-Warning $_;
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
        Gebruiker               = $aRef.Gebruiker
    };    
};
Write-Output $result | ConvertTo-Json -Depth 10;