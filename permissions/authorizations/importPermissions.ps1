####################################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-ImportPermissions
# PowerShell V2
####################################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function ConvertTo-AFASBoolean {
    # A GetConnector can return a boolean as text, and [bool]'false' is $true in PowerShell.
    param (
        [AllowNull()]
        [object]
        $Value
    )
    if ($Value -is [bool]) {
        return $Value
    }
    $parsedValue = $false
    if ([bool]::TryParse([string]$Value, [ref]$parsedValue)) {
        return $parsedValue
    }
    return ([string]$Value -eq '1')
}

function Resolve-AFASProfitError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            if ($null -ne $errorDetailsObject.externalMessage) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.externalMessage
            }
            else {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = "[$($httpErrorObj.ErrorDetails)]"
        }
        Write-Output $httpErrorObj
    }
}

#endregion

try {
    Write-Information 'Starting AFAS Profit permission entitlement import'

    $permissionsToImport = @(
        @{ DisplayName = 'InSite access'; Reference = 'InSi' },
        @{ DisplayName = 'Profit Windows access'; Reference = 'Awin' },
        @{ DisplayName = 'Activate collaboration license'; Reference = 'OcUs' },
        @{ DisplayName = 'AFAS Online Portal administrator'; Reference = 'PoMa' },
        @{ DisplayName = 'AFAS Accept'; Reference = 'AcUs' }
    )

    #Filter - Determine what defines an account entitlement, copy from AFAS Connect cURL. A user with a Upn is considered an account.
    $Filter = "filterfieldids=BcCo,Upn&filtervalues=%5Bis%20niet%20leeg%5D,%5Bis%20niet%20leeg%5D&operatortypes=9,9"

    # Create authorization headers using OAuth client credentials
    $tokenUri = "$($actionContext.Configuration.BaseUri)/oauth/token"
    Write-Verbose "Requesting OAuth access token from [$tokenUri]"

    $tokenRequestBody = @{
        grant_type    = 'client_credentials'
        client_id     = $actionContext.Configuration.ClientId
        client_secret = $actionContext.Configuration.ClientSecret
    }

    $splatTokenParams = @{
        Uri             = $tokenUri
        Method          = 'POST'
        Body            = $tokenRequestBody
        ContentType     = 'application/x-www-form-urlencoded'
        UseBasicParsing = $true
        ErrorAction     = 'Stop'
        Verbose         = $false
    }

    $tokenResponse = Invoke-RestMethod @splatTokenParams

    if ([String]::IsNullOrWhiteSpace([String]$tokenResponse.access_token)) {
        throw "OAuth token endpoint did not return an access_token."
    }

    if ([String]::IsNullOrWhiteSpace([String]$tokenResponse.token_type) -or ([String]$tokenResponse.token_type).ToLowerInvariant() -ne 'bearer') {
        throw "OAuth token endpoint returned an unexpected token_type [$($tokenResponse.token_type)]. Expected [Bearer]."
    }

    $headers = @{
        Authorization = "$($tokenResponse.token_type) $($tokenResponse.access_token)"
        IntegrationId = '45963_140664' # Fixed value - Tools4ever Partner Integration ID
    }

    $take = 1000
    $skip = 0
    $accounts = [System.Collections.Generic.List[object]]::new()

    do {
        $splatQueryParams = @{
            Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.GetConnector)?$filter&skip=$skip&take=$take&orderbyfieldids=UsId"
            Headers         = $headers
            Method          = 'GET'
            ContentType     = 'application/json;charset=utf-8'
            UseBasicParsing = $true
            ErrorAction     = 'Stop'
            Verbose         = $false
        }

        $dataset = Invoke-RestMethod @splatQueryParams
        foreach ($row in @($dataset.rows)) {
            $null = $accounts.Add($row)
        }
        $skip += $take
    } while (@($dataset.rows).Count -eq $take)

    foreach ($permission in $permissionsToImport) {
        $memberReferences = [System.Collections.Generic.List[object]]::new()

        foreach ($account in $accounts) {
            $property = $account.PSObject.Properties[$permission.Reference]
            $permissionValue = if ($null -eq $property) { $null } else { $property.Value }

            if ((ConvertTo-AFASBoolean $permissionValue) -and -not [string]::IsNullOrWhiteSpace($account.BcCo)) {
                $null = $memberReferences.Add([string]$account.BcCo)
            }
        }

        # Return members in batches to stay below HelloID limits.
        $batchSize = 500
        for ($i = 0; $i -lt $memberReferences.Count; $i += $batchSize) {
            $batch = $memberReferences[$i..([Math]::Min($i + $batchSize - 1, $memberReferences.Count - 1))]

            Write-Output @{
                PermissionReference = @{
                    Reference = $permission.Reference
                }
                Description         = [string]$permission.DisplayName
                AccountReferences   = $batch
            }
        }
    }

    Write-Information 'AFAS Profit permission entitlement import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-AFASProfitError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import AFAS Profit permission entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import AFAS Profit permission entitlements. Error: $($ex.Exception.Message)"
    }
}
