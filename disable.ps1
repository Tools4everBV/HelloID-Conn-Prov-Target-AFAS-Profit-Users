#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Disable
#
# Version: 1.2.0
#####################################################
# Initialize default values
$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
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
$getConnector = "T4E_HelloID_Users_v2"
$updateConnector = "KnUser"

#Change mapping here
$account = [PSCustomObject]@{
    'KnUser' = @{
        'Element' = @{
            'Fields' = @{
                # Mutatie code
                'MtCd' = 6

                # E-mail (when setting OutSite to true an email address is required)
                'EmAd' = "$($p.ExternalId)@enyoi.nl" # or e.g. $p.Contact.Personal.Email

                # OutSite
                "Site"    = $true
                # InSite
                "InSi"    = $false
            }
        }
    }
}

# # Troubleshooting
# $aRef = @{
#    Gebruiker = "45963.AndreO"
# }
# $dryRun = $false

$filterfieldid = "Gebruiker"
$filtervalue = $aRef.Gebruiker # Has to match the AFAS value of the specified filter field ($filterfieldid)

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

    if ($null -eq $currentAccount.Gebruiker) {
        throw "No AFAS account found with $($filterfieldid) $($filtervalue)"
    }

    # Check if current EmAd has a different value from mapped value. AFAS will throw an error when trying to update this with the same value
    if ($currentAccount.Email_werk_gebruiker -ne $account.'KnUser'.'Element'.'Fields'.'EmAd' -and $null -ne $account.'KnUser'.'Element'.'Fields'.'EmAd') {
        $propertiesChanged += @('EmAd')
    }
    if ($propertiesChanged) {
        Write-Verbose "Account property(s) required to update: [$($propertiesChanged.name -join ",")]"
        $updateAction = 'Update'
    }
    else {
        $updateAction = 'NoChanges'
    }
}
catch {
    $ex = $PSItem
    $verboseErrorMessage = $ex
    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"

    $auditErrorMessage = Resolve-AFASErrorMessage -ErrorObject $ex
    if ($auditErrorMessage -Like "No AFAS account found*") {
        if (-Not($dryRun -eq $True)) {
            $auditLogs.Add([PSCustomObject]@{
                    Action  = "DisableAccount"
                    Message = "No AFAS account found with $($filterfieldid) $($filtervalue). Possibly already deleted, skipping action."
                    IsError = $true
                })
        }
        else {
            Write-Warning "DryRun: No AFAS account found with $($filterfieldid) $($filtervalue). Possibly already deleted, skipping action."
        }        
    }
    else {
        $success = $false  
        $auditLogs.Add([PSCustomObject]@{
                Action  = "DisableAccount"
                Message = "Error querying AFAS account with $($filterfieldid) $($filtervalue). Error Message: $auditErrorMessage"
                IsError = $True
            })
    }
}

# Update AFAS Account
if ($null -ne $currentAccount.Gebruiker) {
    switch ($updateAction) {
        'Update' {
            try {
                Write-Verbose "Updating AFAS account with userId '$($currentAccount.Gebruiker)'"

                # Create custom account object for update
                $updateAccount = [PSCustomObject]@{
                    'KnUser' = @{
                        'Element' = @{
                            '@UsId'  = $currentAccount.Gebruiker
                            'Fields' = @{
                                # Mutatie code
                                'MtCd' = $account.'KnUser'.'Element'.'Fields'.'MtCd'
                                # Omschrijving
                                "Nm"   = $currentAccount.DisplayName
                            }
                        }
                    }
                }

                # Check if current EmAd has a different value from mapped value. AFAS will throw an error when trying to update this with the same value
                if ('EmAd' -in $propertiesChanged) {
                    # E-mail                       
                    $updateAccount.'KnUser'.'Element'.'Fields'.'EmAd' = $account.'KnUser'.'Element'.'Fields'.'EmAd'
                    $EmAdUpdated = $true
                    if (-not($dryRun -eq $true)) {
                        Write-Information "Updating EmAd '$($currentAccount.Email_werk_gebruiker)' with new value '$($updateAccount.'KnUser'.'Element'.'Fields'.'EmAd')'"
                    }
                    else {
                        Write-Warning "DryRun: Would update EmAd '$($currentAccount.Email_werk_gebruiker)' with new value '$($updateAccount.'KnUser'.'Element'.'Fields'.'EmAd')'"
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

                    $auditLogs.Add([PSCustomObject]@{
                            Action  = "UpdateAccount"
                            Message = "Successfully updated AFAS account with userId '$($aRef.Gebruiker)'"
                            IsError = $false
                        })
                }
                else {
                    Write-Warning "DryRun: Would update AFAS account with userId '$($currentAccount.Gebruiker)'"
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
                        Action  = "UpdateAccount"
                        Message = "Error updating AFAS account with userId '$($currentAccount.Gebruiker)'. Error Message: $auditErrorMessage"
                        IsError = $True
                    })
            }
        }
        'NoChanges' {
            Write-Verbose "No changes to AFAS account with userId '$($currentAccount.Gebruiker)'"

            if (-not($dryRun -eq $true)) {
                $auditLogs.Add([PSCustomObject]@{
                        Action  = "UpdateAccount"
                        Message = "Successfully updated AFAS account with userId '$($aRef.Gebruiker)'. (No Changes needed)"
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: No changes to AFAS account with userId '$($currentAccount.Gebruiker)'"
            }
            break
        }
    }
    
    try {
        Write-Verbose "Disabling AFAS account with userId '$($currentAccount.Gebruiker)'"

        # Create custom account object for update
        $updateAccount = [PSCustomObject]@{
            'KnUser' = @{
                'Element' = @{
                    '@UsId'  = $currentAccount.Gebruiker
                    'Fields' = @{
                        # Mutatie code
                        'MtCd' = $account.'KnUser'.'Element'.'Fields'.'MtCd'
                        # Omschrijving
                        "Nm"   = $currentAccount.DisplayName
                    }
                }
            }
        }
        if($null -ne $account.'KnUser'.'Element'.'Fields'.'Site'){
            $updateAccount.'KnUser'.'Element'.'Fields'.'Site' = $account.'KnUser'.'Element'.'Fields'.'Site'
        }
        if($null -ne $account.'KnUser'.'Element'.'Fields'.'InSi'){
            $updateAccount.'KnUser'.'Element'.'Fields'.'InSi' = $account.'KnUser'.'Element'.'Fields'.'InSi'
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

            $auditLogs.Add([PSCustomObject]@{
                    Action  = "DisableAccount"
                    Message = "Successfully disabled AFAS account with userId '$($aRef.Gebruiker)'"
                    IsError = $false
                })
        }
        else {
            Write-Warning "DryRun: Would disable AFAS account with userId '$($currentAccount.Gebruiker)'"
        }
    }
    catch {
        $ex = $PSItem
        $verboseErrorMessage = $ex
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
    
        $auditErrorMessage = Resolve-AFASErrorMessage -ErrorObject $ex
    
        $success = $false  
        $auditLogs.Add([PSCustomObject]@{
                Action  = "DisableAccount"
                Message = "Error disabling AFAS account with userId '$($currentAccount.Gebruiker)'. Error Message: $auditErrorMessage"
                IsError = $True
            })
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
if ($EmAdUpdated -eq $true) {
    $result.ExportData | Add-Member -MemberType NoteProperty -Name BusinessEmailAddress -Value $($account.KnUser.Element.Fields.EmAd) -Force
}
Write-Output $result | ConvertTo-Json -Depth 10
