####################################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-ImportPermissions
# PowerShell V2
####################################################################

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
            $parsedError = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            $externalMessageProperty = $parsedError.PSObject.Properties['externalMessage']

            if ($null -ne $externalMessageProperty -and -not [string]::IsNullOrWhiteSpace([string]$externalMessageProperty.Value)) {
                $httpErrorObj.FriendlyMessage = $externalMessageProperty.Value
            }
            else {
                $httpErrorObj.FriendlyMessage = $parsedError
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
        @{ DisplayName = 'Profit Windows access'; Reference = 'Awin' }
        @{ DisplayName = 'Activate collaboration license'; Reference = 'OcUs' }
        @{ DisplayName = 'AFAS Online Portal administrator'; Reference = 'PoMa' }
        @{ DisplayName = 'AFAS Accept'; Reference = 'AcUs' }
    )

    # Filter users where EmId (medewerkernummer) en UsId has a value.
    $filter = 'filterfieldids=EmId,UsId&filtervalues=%5Bis%20niet%20leeg%5D&operatortypes=9'

    $base64Token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($actionContext.Configuration.Token))
    $headers = @{
        Authorization = "AfasToken $base64Token"
        IntegrationId = '45963_140664' # Fixed value - Tools4ever Partner Integration ID
    }

    $take = 1000
    $skip = 0
    $accounts = [System.Collections.Generic.List[object]]::new()

    do {
        $uri = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.GetConnector)?$filter&skip=$skip&take=$take&orderbyfieldids=UsId"
        $dataset = Invoke-RestMethod -Method 'GET' -Uri $uri -Headers $headers -ContentType 'application/json;charset=utf-8' -UseBasicParsing -ErrorAction Stop
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

            if (($permissionValue -eq $true) -and -not [string]::IsNullOrWhiteSpace([string]$account.BcCo)) {
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
                DisplayName         = [string]$permission.DisplayName
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
        $errorObj = Resolve-AFAS-ProfitError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import AFAS Profit permission entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import AFAS Profit permission entitlements. Error: $($ex.Exception.Message)"
    }
}
