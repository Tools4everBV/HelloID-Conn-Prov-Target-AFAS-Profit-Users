#################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Import
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-AFAS-ProfitError {
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
    Write-Information 'Starting AFAS Users account entitlement import'
   
    #Filter - Determine what defines an account entitlement, copy from AFAS Connect cURL
    $Filter = "filterfieldids=EmId,UsId&filtervalues=%5Bis%20niet%20leeg%5D&operatortypes=9"

    Write-Verbose "Starting downloading objects through get-connector [$($actionContext.Configuration.GetConnector)]"
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($($actionContext.Configuration.Token)))
    $authValue = "AfasToken $encodedToken"
    $Headers = @{ Authorization = $authValue }
    $Headers.Add("IntegrationId", "45963_140664") # Fixed value - Tools4ever Partner Integration ID

    $take = 1000
    $skip = 0

    do {
        $uri = $($actionContext.Configuration.BaseUri) + "/connectors/" + $($actionContext.Configuration.GetConnector) + "?$Filter&skip=$skip&take=$take&orderbyfieldids=UsId"
        $dataset = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -UseBasicParsing

        foreach ($importedAccount in $dataset.rows) {
            if ([string]::IsNullOrWhiteSpace([string]$importedAccount.BcCo)) {
                continue
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
                Enabled          = ([string]$importedAccount.Bl -eq 'False')
                Data             = $data
            }
        }

        $skip += $take
    } while (@($dataset.rows).count -eq $take)

    Write-Verbose "Downloaded records through get-connector [$($actionContext.Configuration.GetConnector)]"
    
    Write-Information 'AFAS Users account entitlement import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-AFAS-ProfitError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import AFAS Users account entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import AFAS Users account entitlements. Error: $($ex.Exception.Message)"
    }
}
