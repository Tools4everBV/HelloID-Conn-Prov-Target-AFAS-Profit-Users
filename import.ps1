#################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Import
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
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
#endregion functions

try {
    #Filter - Determine what defines an account entitlement, copy from AFAS Connect cURL
    $Filter = "filterfieldids=UsId&filtervalues=%5Bis%20niet%20leeg%5D&operatortypes=9"

    Write-Information "Starting AFAS Users account entitlement import through get-connector [$($actionContext.Configuration.GetConnector)]"

    # Create authorization headers using OAuth client credentials
    $tokenUri = "$($actionContext.Configuration.BaseUri)/oauth/token"
    Write-Verbose "Requesting OAuth access token from [$tokenUri]"

    $tokenRequestBody = @{
        grant_type    = 'client_credentials'
        client_id     = $actionContext.Configuration.ClientId
        client_secret = $actionContext.Configuration.ClientSecret
    }

    $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUri -Body $tokenRequestBody -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing -ErrorAction Stop -Verbose:$false

    if ([String]::IsNullOrWhiteSpace([String]$tokenResponse.access_token)) {
        throw 'OAuth token endpoint did not return an access_token.'
    }

    if ([String]::IsNullOrWhiteSpace([String]$tokenResponse.token_type) -or ([String]$tokenResponse.token_type).ToLowerInvariant() -ne 'bearer') {
        throw "OAuth token endpoint returned an unexpected token_type [$($tokenResponse.token_type)]. Expected [Bearer]."
    }

    $Headers = @{
        Authorization = "$($tokenResponse.token_type) $($tokenResponse.access_token)"
        IntegrationId = '45963_140664' # Fixed value - Tools4ever Partner Integration ID
    }

    $take = 1000
    $skip = 0
    $downloadedRecordCount = 0

    $processedAccountReferences = [System.Collections.Generic.HashSet[string]]::new()

    do {
        $uri = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.GetConnector)?$Filter&skip=$skip&take=$take&orderbyfieldids=UsId"
        $dataset = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -ContentType 'application/json;charset=utf-8' -UseBasicParsing -ErrorAction Stop
        $downloadedRecordCount += @($dataset.rows).Count

        foreach ($importedAccount in $dataset.rows) {
            if ([string]::IsNullOrWhiteSpace([string]$importedAccount.BcCo)) {
                continue
            }

            # Log duplicates so they can be cleaned up in AFAS, but still return them and let HelloID handle it.
            if (-not $processedAccountReferences.Add([string]$importedAccount.BcCo)) {
                Write-Warning "AFAS user [$($importedAccount.UsId)] has person number [$($importedAccount.BcCo)], which is already used as account reference by another user. A person number must resolve to a single AFAS user."
            }

            $data = @{}
            foreach ($field in $($actionContext.ImportFields)) {
                $data[$field] = $importedAccount."$field"
            }

            $displayName = [string]$importedAccount.Nm
            if ([string]::IsNullOrWhiteSpace($displayName)) {
                $displayName = [string]$importedAccount.UsId
            }

            # Return the result
            Write-Output @{
                AccountReference = [string]$importedAccount.BcCo
                DisplayName      = $displayName.substring(0, [System.Math]::Min(100, $displayName.Length))
                UserName         = $importedAccount.UsId
                Enabled          = (-not [bool]$importedAccount.Bl)
                Data             = $data
            }
        }

        $skip += $take
    } while (@($dataset.rows).count -eq $take)

    Write-Information "AFAS Users account entitlement import completed. Downloaded [$downloadedRecordCount] records through get-connector [$($actionContext.Configuration.GetConnector)]"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-AFASProfitError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import AFAS Users account entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import AFAS Users account entitlements. Error: $($ex.Exception.Message)"
    }
}
