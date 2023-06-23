#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Update
#
# Version: 2.0.0
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
                'MtCd' = 1

                # E-mail
                'EmAd' = $p.Accounts.MicrosoftActiveDirectory.mail
                # UPN - Vulling UPN afstemmen met AFAS beheer
                'Upn'  = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName
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
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}

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
    $Headers.Add("IntegrationId", "45963_140664") # Fixed value - Tools4ever Partner Integration ID

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

    # Check if current EmAd or Upn has a different value from mapped value. AFAS will throw an error when trying to update this with the same value
    if ([string]$currentAccount.UPN -ne $account.'KnUser'.'Element'.'Fields'.'Upn' -and $null -ne $account.'KnUser'.'Element'.'Fields'.'Upn') {
        $propertiesChanged += @('Upn')
    }
    if ($currentAccount.Email_werk_gebruiker -ne $account.'KnUser'.'Element'.'Fields'.'EmAd' -and $null -ne $account.'KnUser'.'Element'.'Fields'.'EmAd') {
        $propertiesChanged += @('EmAd')
    }
    if ($propertiesChanged) {
        Write-Verbose "Account property(s) required to update: [$($propertiesChanged -join ",")]"
        $updateAction = 'Update'
    }
    else {
        $updateAction = 'NoChanges'
    }
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = Resolve-AFASErrorMessage -ErrorObject $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"

    if ($auditErrorMessage -Like "No AFAS account found*") {
        $success = $false
        $auditLogs.Add([PSCustomObject]@{
                Action  = "UpdateAccount"
                Message = "No AFAS account found with $($filterfieldid) $($filtervalue). Possibly deleted."
                IsError = $true
            })   
    }
    else {
        $success = $false  
        $auditLogs.Add([PSCustomObject]@{
                Action  = "UpdateAccount"
                Message = "Error querying AFAS account with $($filterfieldid) $($filtervalue). Error Message: $auditErrorMessage"
                IsError = $True
            })
    }
}
# Update AFAS Account
$EmAdUpdated = $false
$UpnUpdated = $false
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
                if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                    $errorObject = Resolve-HTTPError -Error $ex
            
                    $verboseErrorMessage = $errorObject.ErrorMessage
            
                    $auditErrorMessage = Resolve-AFASErrorMessage -ErrorObject $errorObject.ErrorMessage
                }
            
                # If error message empty, fall back on $ex.Exception.Message
                if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
                    $verboseErrorMessage = $ex.Exception.Message
                }
                if ([String]::IsNullOrEmpty($auditErrorMessage)) {
                    $auditErrorMessage = $ex.Exception.Message
                }
            
                Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"            
            
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

#add the data to ExportData if it has actually been updated by helloID. otherwise update the values in HelloID with the current value
if ($UpnUpdated -eq $true) {
    $result.ExportData | Add-Member -MemberType NoteProperty -Name UPN -Value $($account.KnUser.Element.Fields.UPN) -Force
}else{
    $result.ExportData | Add-Member -MemberType NoteProperty -Name UPN -Value $($currentAccount.KnUser.Element.Fields.UPN) -Force
}
if ($EmAdUpdated -eq $true) {
    $result.ExportData | Add-Member -MemberType NoteProperty -Name BusinessEmailAddress -Value $($account.KnUser.Element.Fields.EmAd) -Force
}else{
    $result.ExportData | Add-Member -MemberType NoteProperty -Name UPN -Value $($currentAccount.KnUser.Element.Fields.EmAd) -Force
}


Write-Output $result | ConvertTo-Json -Depth 10
