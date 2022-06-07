# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

$c = $configuration | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$success = $false
$auditLogs = [Collections.Generic.List[PSCustomObject]]::new()

$BaseUri = $c.BaseUri
$Token = $c.Token
$getConnector = "T4E_HelloID_Users_v2"
$updateConnector = "knUser"

$filterfieldid = "Gebruiker"
$filtervalue = $aRef.Gebruiker # Has to match the AFAS value of the specified filter field ($filterfieldid)

try {
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }
    $getUri = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=$filterfieldid&filtervalues=$filtervalue&operatortypes=1"
    $getResponse = Invoke-RestMethod -Method Get -Uri $getUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing

    if ($getResponse.rows.Count -eq 1 -and (![string]::IsNullOrEmpty($getResponse.rows.Gebruiker))) {
        
        # Retrieve current account data for properties to be updated
        $previousAccount = [PSCustomObject]@{
            'KnUser' = @{
                'Element' = @{
                    '@UsId'  = $getResponse.rows.Gebruiker
                    'Fields' = @{
                        # InSite
                        'InSi' = $getResponse.rows.InSite
                    }
                }
            }
        }
       
        # Map the properties to update
        $account = [PSCustomObject]@{
            'KnUser' = @{
                'Element' = @{
                    '@UsId'  = $getResponse.rows.Gebruiker
                    'Fields' = @{
                        # Mutatie code
                        'MtCd' = 6
                        # Omschrijving
                        "Nm"   = $getResponse.rows.DisplayName

                        # Persoon code - Only specify this if you want to update the linked person - Make sure this has a value, otherwise the link will disappear
                        # "BcCo" = $getResponse.rows.Persoonsnummer  

                        # InSite
                        "InSi" = $true
                    }
                }
            }
        }      

        # Set aRef object for use in futher actions
        $aRef = [PSCustomObject]@{
            Gebruiker = $($account.knUser.Values.'@UsId')
        }  

        $body = $account | ConvertTo-Json -Depth 10
        $putUri = $BaseUri + "/connectors/" + $updateConnector
        if (-Not($dryRun -eq $true)) {
            $putResponse = Invoke-RestMethod -Method Put -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing -ErrorAction Stop
        }
        else {
            Write-Information $putUri
            Write-Information $body
        }
        
        $auditLogs.Add([PSCustomObject]@{
                Action  = "DisableAccount"
                Message = "Disabled account with Id $($aRef.Gebruiker)"
                IsError = $false
            })

        $success = $true          
    }
    else {
        $auditLogs.Add([PSCustomObject]@{
                Action  = "DisableAccount"
                Message = "No profit user found with for $($filterfieldid) = $($filtervalue)"
                IsError = $false
            })        

        $success = $false
        Write-Warning "No profit user found with for $($filterfieldid) = $($filtervalue)"
    }        
}
catch {
    $auditLogs.Add([PSCustomObject]@{
            Action  = "DisableAccount"
            Message = "Error disabling account with Id $($aRef.Gebruiker): $($_)"
            IsError = $true
        })
    Write-Warning $_
}

# Send results
$result = [PSCustomObject]@{
    Success          = $success
    AccountReference = $aRef
    AuditLogs        = $auditLogs
    Account          = $account
    PreviousAccount  = $previousAccount

    # Optionally return data for use in other systems
    ExportData       = [PSCustomObject]@{
        Gebruiker = $aRef.Gebruiker
    }
}
Write-Output $result | ConvertTo-Json -Depth 10
