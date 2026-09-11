#################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Create
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
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'
    $createUserEnabled = [bool]$actionContext.Configuration.CreateUser

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

        # 6 - AFAS splits [filtervalues] on the comma. A comma in the value silently shifts all following
        # filter values, which returns a wrong match instead of an error. EscapeDataString does not cover this.
        if ($correlationValue -match ',') {
            throw "Correlation value [$correlationValue] contains a comma. This character is the AFAS filter separator and cannot be used in [filtervalues]"
        }

        # Determine if a user needs to be [created] or [correlated]
        Write-Information "Verifying if a AFAS Profit Users account exists where $correlationField is: [$correlationValue]"

        $notEmptyFilterValue = [uri]::EscapeDataString('[is niet leeg]')
        $splatQueryParams = @{
            Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.GetConnector)?filterfieldids=$($correlationField),BcCo&filtervalues=$([uri]::EscapeDataString($correlationValue)),$notEmptyFilterValue&operatortypes=1,9"
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
        if ([string]::IsNullOrWhiteSpace([string]$correlatedAccount.UsId)) {
            if ($createUserEnabled) {
                $lifecycleProcess = 'CreateAccount'
            }
            else {
                $lifecycleProcess = 'CreateNotEnabled'
            }
        }
        else {
            $lifecycleProcess = 'CorrelateAccount'
        }
    }
    elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple accounts found for person where $correlationField is: [$correlationValue]"
    }    

    # Process
    switch ($lifecycleProcess) {
        'CreateAccount' {
            $newUsId = [string]$actionContext.Data.UsId

            # 8 - Nm is the user description. A Medewerker without UsId has no description yet, while AFAS requires it.
            $userDescription = [string]$correlatedAccount.Nm
            if ([string]::IsNullOrWhiteSpace($userDescription)) {
                $userDescription = $newUsId
            }

            # Build a base payload with permission-related flags managed by the script.
            $fieldsToCreate = [ordered]@{
                BcCo = [string]$correlatedAccount.BcCo
                Nm   = $userDescription
                Acon = 'false'
                Abac = 'false'
                Acom = 'false'
                InSi = 'false'
            }

            # 7 - UsId is sent as element key and EmId is a GetConnector correlation field only.
            # Both are not valid KnUser fields and are rejected by AFAS when present in the payload.
            $fieldsToExcludeFromPayload = @('UsId', 'EmId')

            # Add/overwrite remaining fields from mapping data.
            foreach ($property in $actionContext.Data.PSObject.Properties) {
                if ($property.Name -notin $fieldsToExcludeFromPayload) {
                    $fieldsToCreate[$property.Name] = $property.Value
                }
            }

            $createAccount = [PSCustomObject]@{
                KnUser = @{
                    Element = @{
                        '@UsId' = $newUsId
                        Fields  = $fieldsToCreate
                    }
                }
            }

            $body = ($createAccount | ConvertTo-Json -Depth 10)
            $fieldsInPayload = ($fieldsToCreate.Keys | ForEach-Object { [string]$_ }) -join ', '
            $splatCreateParams = @{
                Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.UpdateConnector)"
                Method          = 'POST'
                Headers         = $authHeader
                Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                ContentType     = 'application/json;charset=utf-8'
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Creating and correlating AFAS account [$newUsId]. Fields in create payload: [$fieldsInPayload]"
                $null = Invoke-RestMethod @splatCreateParams -Verbose:$false

                $outputContext.Data = $actionContext.Data | Select-Object -Property $outputContext.Data.PSObject.Properties.Name
                $outputContext.AccountReference = [string]$fieldsToCreate['BcCo']

                $auditLogMessage = "Created and correlated AFAS account with accountReference: [$($outputContext.AccountReference)]. Account property(s) set: [$fieldsInPayload]"
            }
            else {
                Write-Information "[DryRun] Create and correlate AFAS account [$newUsId], will be executed during enforcement. Fields in create payload: [$fieldsInPayload]"
                $outputContext.Data = $actionContext.Data | Select-Object -Property $outputContext.Data.PSObject.Properties.Name
                $outputContext.AccountReference = [string]$fieldsToCreate['BcCo']
                $auditLogMessage = "[DryRun] Would create and correlate AFAS account with accountReference: [$($outputContext.AccountReference)]. Account property(s) to set: [$fieldsInPayload]"
            }

            $outputContext.success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'CreateAccount'
                    Message = $auditLogMessage
                    IsError = $false
                })
            break
        }

        'CreateNotEnabled' {
            $auditLogMessage = "Correlated AFAS account has no UsId for [$($correlationField)] = [$($correlationValue)], but configuration [CreateUser] is disabled."
            Write-Information $auditLogMessage

            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'CorrelateAccount'
                    Message = $auditLogMessage
                    IsError = $true
                })
            break
        }

        'CorrelateAccount' {
            Write-Information "Correlating AFAS account [$($correlatedAccount.UsId)]"

            $outputContext.Data = $correlatedAccount | Select-Object -Property $outputContext.Data.PSObject.Properties.Name
            $outputContext.AccountReference = [string]$correlatedAccount.BcCo
            $outputContext.AccountCorrelated = $true
            $outputContext.success = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'CorrelateAccount'
                    Message = $auditLogMessage
                    IsError = $false
                })
            break
        }

        'NotFound' {
            $auditLogMessage = "No AFAS account found where [$($correlationField)] = [$($correlationValue)]. Cannot create user without correlated person number [BcCo]."
            Write-Information $auditLogMessage

            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'CreateAccount'
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
        $errorObj = Resolve-AFASProfitError -ErrorObject $ex
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