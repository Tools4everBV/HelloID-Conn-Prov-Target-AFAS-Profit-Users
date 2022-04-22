# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [Collections.Generic.List[PSCustomObject]]::new()

$BaseUri = $c.BaseUri
$Token = $c.Token
$RelationNumber = $c.RelationNumber
$updateUserId = $c.updateUserId
$getConnector = "T4E_HelloID_Users_v2"
$updateConnector = "knUser"

$filterfieldid = "Medewerker"
$filtervalue = $p.externalId # Has to match the AFAS value of the specified filter field ($filterfieldid)
$emailaddress = $p.Accounts.MicrosoftActiveDirectory.mail
$userPrincipalName = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName
$userId = $RelationNumber + "." + $p.Custom.employeeNumber
# Only used for new users, for existing users, the current displayname of the AFAS user is used
$userDescription = $p.Accounts.MicrosoftActiveDirectory.displayName

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

        if ($updateUserId -eq $true) {

            # If User ID doesn't match naming convention, update this
            if ($getResponse.rows.Gebruiker -ne $userId) {
                $account = [PSCustomObject]@{
                    'KnUser' = @{
                        'Element' = @{
                            '@UsId'  = $getResponse.rows.Gebruiker
                            'Fields' = @{
                                # Mutatie code
                                'MtCd'    = 4
                                # Omschrijving
                                "Nm"      = $getResponse.rows.DisplayName

                                # Persoon code - Only specify this if you want to update the linked person - Make sure this has a value, otherwise the link will disappear
                                # "BcCo" = $getResponse.rows.Persoonsnummer
                                # Nieuwe gebruikerscode
                                "UsIdNew" = $userId
                            }
                        }
                    }
                }

                $body = $account | ConvertTo-Json -Depth 10
                $putUri = $BaseUri + "/connectors/" + $updateConnector
                if (-Not($dryRun -eq $true)) {
                    $putResponse = Invoke-RestMethod -Method Put -Uri $putUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing -ErrorAction Stop
                    Write-Information "UserId [$($getResponse.rows.Gebruiker)] updated to [$userId]"
                }
                else {
                    Write-Information $putUri
                    Write-Information $body
                }     

                # Get Person data to make sure we have the latest fields (after update of UserId)
                $getUri = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=$filterfieldid&filtervalues=$filtervalue&operatortypes=1"
                $getResponse = Invoke-RestMethod -Method Get -Uri $getUri -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing
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
            Write-Information "Updating UPN '$($getResponse.rows.UPN)' with new value '$userPrincipalName'"
            # Set variable to indicate update of Upn has occurred (for export data object)
            $UpnUpdated = $true
        }

        # If '$emailAdddres' does not match current 'EmAd', add 'EmAd' to update body. AFAS will throw an error when trying to update this with the same value
        if ($getResponse.rows.Email_werk_gebruiker -ne $emailaddress) {
            # E-mail
            $account.'KnUser'.'Element'.'Fields' += @{'EmAd' = $emailaddress }
            Write-Information "Updating BusinessEmailAddress '$($getResponse.rows.Email_werk_gebruiker)' with new value '$emailaddress'"
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
                Action  = "CreateAccount"
                Message = "Correlated to and updated fields of account with id $($aRef.Gebruiker)"
                IsError = $false
            })

        $success = $true
    }
    else {

        # Account doesn't exist this person. Creating account

        #Change mapping here
        $account = [PSCustomObject]@{
            'KnUser' = @{
                'Element' = @{
                    # Gebruiker
                    '@UsId'  = $userId
                    'Fields' = @{
                        # Mutatie code
                        'MtCd'    = 1
                        # Omschrijving
                        "Nm"      = $userDescription

                        # Persoon code
                        "BcCo"    = $getResponse.rows.Persoonsnummer
                        # Nieuwe gebruikerscode
                        "UsIdNew" = $userId

                        # E-mail
                        'EmAd'    = $emailaddress
                        # UPN
                        'Upn'     = $userPrincipalName

                        # Profit Windows
                        "Awin"    = $false
                        # Connector
                        "Acon"    = $false
                        # Reservekopieen via commandline
                        "Abac"    = $false
                        # Commandline
                        "Acom"    = $false

                        # Outsite
                        "Site"    = $false
                        # InSite
                        "InSi"    = $true

                        # Meewerklicentie actieveren
                        "OcUs"    = $false
                        # AFAS Online Portal-beheerder
                        "PoMa"    = $false
                        # AFAS Accept
                        "AcUs"    = $false

                        # Wachtwoord
                        "Pw"      = "GHJKL!!!23456gfdgf" # dummy pwd, not used, but required

                        <#
                        # Groep
                        'GrId' = "groep1"
                        # Groep omschrijving
                        'GrDs' = "Groep omschrijving1"
                        # Afwijkend e-mailadres
                        "XOEA" = "test1@a-mail.nl"
                        # Voorkeur site
                        "InLn" = "1043" # NL
                        # Meewerklicentie actieveren
                        "OcUs" = $false
                        # AFAS Online Portal-beheerder
                        "PoMa" = $false
                        # AFAS Accept
                        "AcUs" = $false
                        #>
                    }
                }
            }
        }

        # Set aRef object for use in futher actions
        $aRef = [PSCustomObject]@{
            Gebruiker = $($account.knUser.Values.'@UsId')
        }

        $body = $account | ConvertTo-Json -Depth 10
        $postUri = $BaseUri + "/connectors/" + $updateConnector
        if (-Not($dryRun -eq $true)) {
            $postResponse = Invoke-RestMethod -Method Post -Uri $postUri -Body $body -ContentType "application/json;charset=utf-8" -Headers $Headers -UseBasicParsing -ErrorAction Stop
        }
        else {
            Write-Information $postUri
            Write-Information $body
        }

        $auditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount"
                Message = "Created account with Id $($aRef.Gebruiker)"
                IsError = $false
            })

        $success = $true
    }
}
catch {
    $errResponse = $_
    if ($errResponse -like "*Aan de gekozen persoon is al een gebruiker gekoppeld*") {
        $auditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount"
                Message = "Correlated to account with id $($aRef.Gebruiker)"
                IsError = $false
            })

        $success = $true
    }
    else {
        $auditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount"
                Message = "Error creating account with Id $($aRef.Gebruiker): $($_)"
                IsError = $true
            })
        Write-Warning $_
    }
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