#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Enable
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
                'MtCd' = 6

                # OutSite
                "Site" = $false
                # InSite
                "InSi" = $true
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
                Action  = "EnableAccount"
                Message = "No AFAS account found with $($filterfieldid) $($filtervalue). Possibly deleted."
                IsError = $true
            })    
    }
    else {
        $success = $false  
        $auditLogs.Add([PSCustomObject]@{
                Action  = "EnableAccount"
                Message = "Error querying AFAS account with $($filterfieldid) $($filtervalue). Error Message: $auditErrorMessage"
                IsError = $True
            })
    }
}
# Update AFAS Account
if ($null -ne $currentAccount.Gebruiker) {
    try {
        Write-Verbose "Enabling AFAS account with userId '$($currentAccount.Gebruiker)'"

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
        if ($null -ne $account.'KnUser'.'Element'.'Fields'.'Site') {
            $updateAccount.'KnUser'.'Element'.'Fields'.'Site' = $account.'KnUser'.'Element'.'Fields'.'Site'
        }
        if ($null -ne $account.'KnUser'.'Element'.'Fields'.'InSi') {
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
                    Action  = "EnableAccount"
                    Message = "Successfully enabled AFAS account with userId '$($aRef.Gebruiker)'"
                    IsError = $false
                })
        }
        else {
            Write-Warning "DryRun: Would enable AFAS account with userId '$($currentAccount.Gebruiker)'"
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
    
        $success = $false  
        $auditLogs.Add([PSCustomObject]@{
                Action  = "EnableAccount"
                Message = "Error enabling AFAS account with userId '$($currentAccount.Gebruiker)'. Error Message: $auditErrorMessage"
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

Write-Output $result | ConvertTo-Json -Depth 10