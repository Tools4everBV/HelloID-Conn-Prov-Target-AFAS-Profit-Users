#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Create
#
# Version: 1.2.0
#####################################################
# Initialize default values
$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $true # Set to true at start, because only when an error occurs it is set to false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Used to connect to AFAS API endpoints
$BaseUri = $c.BaseUri
$Token = $c.Token
$RelationNumber = $c.RelationNumber
$updateUserOnCorrelate = $c.updateUserOnCorrelate
$updateUserId = $c.updateUserId
$getConnector = "T4E_HelloID_Users_v2"
$updateConnector = "KnUser"

#Change mapping here
$userId = $RelationNumber + "." + $p.ExternalId
# Shorten userId to max 20 chars.
$userId = $userId.substring(0, [System.Math]::Min(20, $userId.Length))
$account = [PSCustomObject]@{
    'KnUser' = @{
        'Element' = @{
            # Gebruiker
            '@UsId'  = $userId
            'Fields' = @{
                # Mutatie code
                'MtCd'    = 1
                # Omschrijving
                "Nm"      = $p.Accounts.MicrosoftActiveDirectory.displayName # Only used for new users, for existing users, the current displayname of the AFAS user is used

                # Nieuwe gebruikerscode
                "UsIdNew" = $userId

                # E-mail
                'EmAd'    = $p.Accounts.MicrosoftActiveDirectory.mail
                # UPN - Vulling UPN afstemmen met AFAS beheer
                'Upn'     = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName

                # Profit Windows
                "Awin"    = $false
                # Connector
                "Acon"    = $false
                # Reservekopieen via commandline
                "Abac"    = $false
                # Commandline
                "Acom"    = $false

                # Outsite
                "Site"    = $true
                # InSite
                "InSi"    = $false

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

# Troubleshooting
# $dryRun = $false

$filterfieldid = "Medewerker"
$filtervalue = $p.externalId # Has to match the AFAS value of the specified filter field ($filterfieldid)

#region functions
function Resolve-AFASErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        try {
            $errorObjectConverted = $ErrorObject | ConvertFrom-Json -ErrorAction Stop

            if ($null -ne $errorObjectConverted.externalMessage) {
                $errorMessage = $errorObjectConverted.externalMessage
            }
            else {
                $errorMessage = $errorObjectConverted
            }
        }
        catch {
            $errorMessage = "$($ErrorObject.Exception.Message)"
        }

        Write-Output $errorMessage
    }
}
#endregion functions

# Get current AFAS employee and verify if a user must be either [created], [updated and correlated] or just [correlated]
try {
    Write-Verbose "Querying AFAS employee with $($filterfieldid) $($filtervalue)"

    # Create authorization headers
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Token))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }

    $splatWebRequest = @{
        Uri             = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=$filterfieldid&filtervalues=$filtervalue&operatortypes=1"
        Headers         = $headers
        Method          = 'GET'
        ContentType     = "application/json;charset=utf-8"
        UseBasicParsing = $true
    }
    $currentAccount = (Invoke-RestMethod @splatWebRequest -Verbose:$false).rows

    if ($null -ne $currentAccount.Gebruiker) {
        Write-Verbose "Successfully queried AFAS account with $($filterfieldid) $($filtervalue): $($currentAccount.Gebruiker)"
        
        if ($updateUserOnCorrelate -eq $true) {
            $action = 'Update-Correlate'

            # Check if current EmAd or Upn has a different value from mapped value. AFAS will throw an error when trying to update this with the same value
            if ([string]$currentAccount.UPN -ne $account.'KnUser'.'Element'.'Fields'.'Upn' -and $null -ne $account.'KnUser'.'Element'.'Fields'.'Upn') {
                $propertiesChanged += @('Upn')
            }
            if ($currentAccount.Email_werk_gebruiker -ne $account.'KnUser'.'Element'.'Fields'.'EmAd' -and $null -ne $account.'KnUser'.'Element'.'Fields'.'EmAd') {
                $propertiesChanged += @('EmAd')
            }
            if ($true -eq $updateUserId -and $currentAccount.Gebruiker -ne $account.'KnUser'.'Element'.'Fields'.'UsIdNew' -and $null -ne $account.'KnUser'.'Element'.'Fields'.'UsIdNew') {
                $propertiesChanged += @('UsId')
            }

            if ($propertiesChanged) {
                Write-Verbose "Account property(s) required to update: [$($propertiesChanged -join ",")]"
                $updateAction = 'Update'
            }
            else {
                $updateAction = 'NoChanges'
            }
        }
        else {
            $action = 'Correlate'
        }
    } 
    else {
        Write-Verbose "Could not query AFAS account with $($filterfieldid) $($filtervalue). Creating new acount"
        $action = 'Create'
    }
}
catch {
    $ex = $PSItem
    $verboseErrorMessage = $ex
    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"

    $auditErrorMessage = Resolve-AFASErrorMessage -ErrorObject $ex
    $success = $false  
    $auditLogs.Add([PSCustomObject]@{
            Action  = "CreateAccount"
            Message = "Error querying AFAS account with $($filterfieldid) $($filtervalue). Error Message: $auditErrorMessage"
            IsError = $True
        })
}

# Either create, update and correlate or just correlate AFAS account
$EmAdUpdated = $false
$UpnUpdated = $false
switch ($action) {
    'Create' {
        try {
            Write-Verbose "Creating AFAS account with userId $($account.'KnUser'.'Element'.'@UsId')"

            # Set Persoon code to link to correct person
            $account.'KnUser'.'Element'.'Fields'.'BcCo' = $currentAccount.Persoonsnummer

            $body = ($account | ConvertTo-Json -Depth 10)
            $splatWebRequest = @{
                Uri             = $BaseUri + "/connectors/" + $updateConnector
                Headers         = $headers
                Method          = 'POST'
                Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                ContentType     = "application/json;charset=utf-8"
                UseBasicParsing = $true
            }

            if (-not($dryRun -eq $true)) {
                $createdAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false
                # Set aRef object for use in futher actions
                $aRef = [PSCustomObject]@{
                    Gebruiker = $($account.knUser.Values.'@UsId')
                }

                $auditLogs.Add([PSCustomObject]@{
                        Action  = "CreateAccount"
                        Message = "Successfully created AFAS account with userId $($aRef.Gebruiker)"
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would create AFAS account with userId $($account.'KnUser'.'Element'.'@UsId')"
            }
            break
        }
        catch {
            $ex = $PSItem
            $verboseErrorMessage = $ex
            Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
        
            $auditErrorMessage = Resolve-AFASErrorMessage -ErrorObject $ex
            $success = $false  
            $auditLogs.Add([PSCustomObject]@{
                    Action  = "CreateAccount"
                    Message = "Error creating AFAS account with userId $($aRef.Gebruiker). Error Message: $auditErrorMessage"
                    IsError = $True
                })
        }
    }
    'Update-Correlate' {
        Write-Verbose "Updating and correlating AFAS account with userId $($currentAccount.Gebruiker)"

        switch ($updateAction) {
            'Update' {
                try {
                    # If User ID doesn't match naming convention, update this
                    if ($updateUserId -eq $true -and 'UsId' -in $propertiesChanged) {
                        Write-Verbose "Updating AFAS account with userId $($currentAccount.Gebruiker) to new userId '$($account.'KnUser'.'Element'.'Fields'.'UsIdNew')'"

                        # Create custom account object for update
                        $updateAccountUserId = [PSCustomObject]@{
                            'KnUser' = @{
                                'Element' = @{
                                    '@UsId'  = $currentAccount.Gebruiker
                                    'Fields' = @{
                                        # Mutatie code
                                        'MtCd'    = 4
                                        # Omschrijving
                                        "Nm"      = $currentAccount.DisplayName

                                        # Nieuwe gebruikerscode
                                        "UsIdNew" = $($account.'KnUser'.'Element'.'Fields'.'UsIdNew')
                                    }
                                }
                            }
                        }

                        $body = ($updateAccountUserId | ConvertTo-Json -Depth 10)
                        $splatWebRequest = @{
                            Uri             = $BaseUri + "/connectors/" + $updateConnector
                            Headers         = $headers
                            Method          = 'PUT'
                            Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                            ContentType     = "application/json;charset=utf-8"
                            UseBasicParsing = $true
                        }

                        if (-not($dryRun -eq $true)) {
                            $updatedAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false
                            # Set aRef object for use in futher actions
                            $aRef = [PSCustomObject]@{
                                Gebruiker = $($account.knUser.Values.'@UsId')
                            }
            
                            $auditLogs.Add([PSCustomObject]@{
                                    Action  = "CreateAccount"
                                    Message = "Successfully updated AFAS account with userId $($currentAccount.Gebruiker) to new userId '$($updateAccountUserId.'KnUser'.'Element'.'Fields'.'UsIdNew')'"
                                    IsError = $false
                                })
                        }
                        else {
                            Write-Warning "DryRun: Would update AFAS account with userId $($currentAccount.Gebruiker) to new userId '$($updateAccountUserId.'KnUser'.'Element'.'Fields'.'UsIdNew')'"
                        }
        
                        # Get Person data to make sure we have the latest fields (after update of UserId)
                        $splatWebRequest = @{
                            Uri             = $BaseUri + "/connectors/" + $getConnector + "?filterfieldids=$filterfieldid&filtervalues=$filtervalue&operatortypes=1"
                            Headers         = $headers
                            Method          = 'GET'
                            ContentType     = "application/json;charset=utf-8"
                            UseBasicParsing = $true
                        }
                        $currentAccount = (Invoke-RestMethod @splatWebRequest -Verbose:$false).rows
                    }
                }
                catch {
                    $ex = $PSItem
                    $verboseErrorMessage = $ex
                    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
                    
                    $auditErrorMessage = Resolve-AFASErrorMessage -ErrorObject $ex
                    
                    $success = $false  
                    $auditLogs.Add([PSCustomObject]@{
                            Action  = "CreateAccount"
                            Message = "Error updating AFAS account with userId $($currentAccount.Gebruiker) to new userId '$($account.'KnUser'.'Element'.'Fields'.'UsIdNew')'. Error Message: $auditErrorMessage"
                            IsError = $True
                        })
                }

                try {
                    Write-Verbose "Updating AFAS account with userId $($currentAccount.Gebruiker)"

                    # Create custom account object for update
                    $updateAccount = [PSCustomObject]@{
                        'KnUser' = @{
                            'Element' = @{
                                '@UsId'  = $currentAccount.Gebruiker
                                'Fields' = @{
                                    # Mutatie code
                                    'MtCd' = 1
                                    # Omschrijving
                                    "Nm"   = $currentAccount.DisplayName
                                }
                            }
                        }
                    }

                    # Check if current EmAd or Upn has a different value from mapped value. AFAS will throw an error when trying to update this with the same value
                    if ('UPN' -in $propertiesChanged) {
                        # UPN
                        $updateAccount.'KnUser'.'Element'.'Fields'.'Upn' = $account.'KnUser'.'Element'.'Fields'.'Upn'
                        $UpnUpdated = $true
                        if (-not($dryRun -eq $true)) {
                            Write-Information "Updating UPN '$($currentAccount.UPN)' with new value '$($updateAccount.'KnUser'.'Element'.'Fields'.'Upn')'"
                        }
                        else {
                            Write-Warning "DryRun: Would update UPN '$($currentAccount.UPN)' with new value '$($updateAccount.'KnUser'.'Element'.'Fields'.'Upn')'"
                        }
                    }

                    if ('EmAd' -in $propertiesChanged) {
                        # E-mail                       
                        $updateAccount.'KnUser'.'Element'.'Fields'.'EmAd' = $account.'KnUser'.'Element'.'Fields'.'EmAd'
                        $EmAdUpdated = $true
                        if (-not($dryRun -eq $true)) {
                            Write-Information "Updating UPN '$($currentAccount.Email_werk_gebruiker)' with new value '$($updateAccount.'KnUser'.'Element'.'Fields'.'EmAd')'"
                        }
                        else {
                            Write-Warning "DryRun: Would update UPN '$($currentAccount.Email_werk_gebruiker)' with new value '$($updateAccount.'KnUser'.'Element'.'Fields'.'EmAd')'"
                        }
                    }

                    $body = ($updateAccount | ConvertTo-Json -Depth 10)
                    $splatWebRequest = @{
                        Uri             = $BaseUri + "/connectors/" + $updateConnector
                        Headers         = $headers
                        Method          = 'PUT'
                        Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                        ContentType     = "application/json;charset=utf-8"
                        UseBasicParsing = $true
                    }

                    if (-not($dryRun -eq $true)) {
                        $updatedAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false
                        # Set aRef object for use in futher actions
                        $aRef = [PSCustomObject]@{
                            Gebruiker = $($account.knUser.Values.'@UsId')
                        }
        
                        $auditLogs.Add([PSCustomObject]@{
                                Action  = "CreateAccount"
                                Message = "Successfully updated AFAS account with userId $($aRef.Gebruiker)"
                                IsError = $false
                            })
                    }
                    else {
                        Write-Warning "DryRun: Would update AFAS account with userId $($currentAccount.Gebruiker)"
                    }
                    break
                }
                catch {
                    $ex = $PSItem
                    $verboseErrorMessage = $ex
                    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
                    
                    $auditErrorMessage = Resolve-AFASErrorMessage -ErrorObject $ex
                    
                    $success = $false  
                    $auditLogs.Add([PSCustomObject]@{
                            Action  = "CreateAccount"
                            Message = "Error updating AFAS account with userId $($currentAccount.Gebruiker). Error Message: $auditErrorMessage"
                            IsError = $True
                        })
                }
            }
            'NoChanges' {
                Write-Verbose "No changes to AFAS account with userId $($currentAccount.Gebruiker)"

                if (-not($dryRun -eq $true)) {
                    # Set aRef object for use in futher actions
                    $aRef = [PSCustomObject]@{
                        Gebruiker = $($currentAccount.Gebruiker)
                    }

                    $auditLogs.Add([PSCustomObject]@{
                            Action  = "CreateAccount"
                            Message = "Successfully updated AFAS account with userId $($aRef.Gebruiker). (No Changes needed)"
                            IsError = $false
                        })
                }
                else {
                    Write-Warning "DryRun: No changes to AFAS account with userId $($currentAccount.Gebruiker)"
                }
                break
            }
        }
        break
    }
    'Correlate' {
        Write-Verbose "Correlating AFAS account with userId $($currentAccount.Gebruiker)"

        if (-not($dryRun -eq $true)) {
            # Set aRef object for use in futher actions
            $aRef = [PSCustomObject]@{
                Gebruiker = $($currentAccount.Gebruiker)
            }

            $auditLogs.Add([PSCustomObject]@{
                    Action  = "CreateAccount"
                    Message = "Successfully correlated AFAS account with userId $($aRef.Gebruiker)"
                    IsError = $false
                })
        }
        else {
            Write-Warning "DryRun: Would correlate AFAS account with userId $($currentAccount.Gebruiker)"
        }
        break
    }
}

# Send results
$result = [PSCustomObject]@{
    Success          = $success
    AccountReference = $aRef
    AuditLogs        = $auditLogs
    Account          = $account

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