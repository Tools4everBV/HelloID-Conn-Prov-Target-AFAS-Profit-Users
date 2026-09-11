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

            # 16 - AFAS returns the readable error in [externalMessage].
            if ($null -ne $errorDetailsObject.externalMessage) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.externalMessage
            }
            else {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = "[$($httpErrorObj.ErrorDetails)]"
            Write-Warning $_.Exception.Message
        }
        Write-Output $httpErrorObj
    }
}
#endregion functions

try {
    #Filter - Determine what defines an account entitlement, copy from AFAS Connect cURL
    $Filter = "filterfieldids=EmId,UsId&filtervalues=%5Bis%20niet%20leeg%5D&operatortypes=9"

    Write-Information "Starting AFAS Users account entitlement import through get-connector [$($actionContext.Configuration.GetConnector)]"

    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($($actionContext.Configuration.Token)))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }
    $Headers.Add("IntegrationId", "45963_140664") # Fixed value - Tools4ever Partner Integration ID

    $take = 1000
    $skip = 0
    $downloadedRecordCount = 0

    # 18 - BcCo is the account reference. Track it to detect persons with more than one AFAS user.
    $processedAccountReferences = [System.Collections.Generic.HashSet[string]]::new()

    do {
        $uri = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.GetConnector)?$Filter&skip=$skip&take=$take&orderbyfieldids=UsId"
        $dataset = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -UseBasicParsing
        $downloadedRecordCount += @($dataset.rows).Count

        foreach ($importedAccount in $dataset.rows) {
            if ([string]::IsNullOrWhiteSpace([string]$importedAccount.BcCo)) {
                continue
            }

            # 18 - Log duplicates so they can be cleaned up in AFAS, but still return them and let HelloID handle it.
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
                # 9 - Bl is a boolean in the GetConnector, so evaluate it as one instead of via a string compare.
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
