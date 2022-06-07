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
$emailaddress = $null # or "$personId@customer.nl" # Unique value based of PersonId because at the revoke action we want to clear the unique fields.
$userPrincipalName = $null # or "$personId@customer.nl" # Unique value based of PersonId because at the revoke action we want to clear the unique fields

$EmAdUpdated = $false
$UpnUpdated = $false

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
                        # E-mail
                        'EmAd' = $getResponse.rows.Email_werk_gebruiker
                        # UPN
                        'Upn'  = $getResponse.rows.UPN
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
                        'MtCd' = 1
                        # Omschrijving
                        "Nm"   = $getResponse.rows.DisplayName
                    }
                }
            }
        }

        # If '$userPrincipalName' does not match current 'UPN', add 'UPN' to update body. AFAS will throw an error when trying to update this with the same value
        if ($getResponse.rows.UPN -ne $userPrincipalName) {
            # vulling UPN afstemmen met AFAS beheer
            # UPN
            $account.'KnUser'.'Element'.'Fields' += @{'Upn' = $userPrincipalName }
            Write-Verbose -Verbose "Updating UPN '$($getResponse.rows.UPN)' with new value '$userPrincipalName'"
            # Set variable to indicate update of Upn has occurred (for export data object)
            $UpnUpdated = $true
        }

        # If '$emailAdddres' does not match current 'EmAd', add 'EmAd' to update body. AFAS will throw an error when trying to update this with the same value
        if ($getResponse.rows.Email_werk_gebruiker -ne $emailaddress) {
            # E-mail
            $account.'KnUser'.'Element'.'Fields' += @{'EmAd' = $emailaddress }
            Write-Verbose -Verbose "Updating BusinessEmailAddress '$($getResponse.rows.Email_werk_gebruiker)' with new value '$emailaddress'"
            # Set variable to indicate update of EmAd has occurred (for export data object)
            $EmAdUpdated = $true
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
                Action  = "DeleteAccount"
                Message = "Updated fields of account with id $($aRef.Gebruiker)"
                IsError = $false
            })

        $success = $true          
    }
    else {
        $auditLogs.Add([PSCustomObject]@{
                Action  = "DeleteAccount"
                Message = "No profit user found with for $($filterfieldid) = $($filtervalue)"
                IsError = $false
            })        

        $success = $false
        Write-Warning "No profit user found with for $($filterfieldid) = $($filtervalue)"
    }       
}
catch {
    $auditLogs.Add([PSCustomObject]@{
            Action  = "UpdateAccount"
            Message = "Error updating fields of account with Id $($aRef.Gebruiker): $($_)"
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

# Only add the data to ExportData if it has actually been updated, since we want to store the data HelloID has sent
if ($UpnUpdated -eq $true) {
    $result.ExportData | Add-Member -MemberType NoteProperty -Name UPN -Value $($account.KnUser.Element.Fields.UPN) -Force
}
if ($EmAdUpdated -eq $true) {
    $result.ExportData | Add-Member -MemberType NoteProperty -Name BusinessEmailAddress -Value $($account.KnUser.Element.Fields.EmAd) -Force
}
Write-Output $result | ConvertTo-Json -Depth 10
