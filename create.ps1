#################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Create
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
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    # Encode token for AFAS API authentication
    $base64Token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($actionContext.Configuration.Token))
    $authHeader = @{
        "Authorization" = "AfasToken $base64Token"
        "IntegrationId" = "45963_140664" # Fixed value - Tools4ever Partner Integration ID
    }

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Determine if a user needs to be [created] or [correlated]
        Write-Information "Verifying if a AFAS Profit Users account exists where $correlationField is: [$correlationValue]"

        $splatQueryParams = @{
            Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.GetConnector)?filterfieldids=$($correlationField)&filtervalues=$([uri]::EscapeDataString($correlationValue))&operatortypes=1"
            Method          = 'GET'
            Headers         = $authHeader
            ContentType     = "application/json;charset=utf-8"
            UseBasicParsing = $true
        }

        $correlatedAccount = @((Invoke-RestMethod @splatQueryParams).rows)
    }
    else {
        throw 'Correlation is not enabled but this connector only supports correlation.'
    }

    if ($correlatedAccount.Count -eq 0) {
        $lifecycleProcess = 'NotFound'
    }
    elseif ($correlatedAccount.Count -eq 1) {
        $correlatedAccount = $correlatedAccount[0]
        $lifecycleProcess = 'CorrelateAccount'
    }
    elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple accounts found for person where $correlationField is: [$correlationValue]"
    }    

    # Process
    switch ($lifecycleProcess) {
        'CorrelateAccount' {
            Write-Information "Correlating AFAS account [$($correlatedAccount.Persoonsnummer)]"

            $outputContext.Data = $correlatedAccount | Select-Object -Property $outputContext.Data.PSObject.Properties.Name
            $outputContext.AccountReference = $correlatedAccount.Persoonsnummer
            $outputContext.AccountCorrelated = $true
            $outputContext.success = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = $lifecycleProcess
                    Message = $auditLogMessage
                    IsError = $false
                })
            break
        }
        'NotFound' {
            $auditLogMessage = "No account found where [$($correlationField)] = [$($correlationValue)] while this connector only supports correlation."
            Write-Information $auditLogMessage
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $auditLogMessage
                    IsError = $true
                })
            break
        }
    }
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-AFAS-ProfitError -ErrorObject $ex
        $auditLogMessage = "Could not create or correlate AFAS-Profit account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not create or correlate AFAS-Profit account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}