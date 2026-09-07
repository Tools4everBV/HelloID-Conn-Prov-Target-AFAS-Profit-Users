##################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Delete
# PowerShell V2
##################################################

#TODO: Remove hardcoded values
# $actionContext.References.Account = "45963.AndreO"
# $actionContext.DryRun = $false

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
    # Verify if [accountReference] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-Information 'Verifying if an AFAS Profit account exists'
    $base64Token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($actionContext.Configuration.Token))
    $headers = @{
        Authorization = "AfasToken $base64Token"
        IntegrationId = '45963_140664' # Fixed value - Tools4ever Partner Integration ID
    }

    $splatQueryParams = @{
        Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.GetConnector)?filterfieldids=BcCo&filtervalues=$([uri]::EscapeDataString($actionContext.References.Account))&operatortypes=1"
        Headers         = $headers
        Method          = 'GET'
        ContentType     = 'application/json;charset=utf-8'
        UseBasicParsing = $true
        ErrorAction     = 'Stop'
    }

    $correlatedAccount = @((Invoke-RestMethod @splatQueryParams).rows)

    if ($correlatedAccount.Count -eq 1) {
        $correlatedAccount = $correlatedAccount[0]
        $lifecycleProcess = 'DeleteAccount'

        $outputContext.PreviousData = $correlatedAccount | Select-Object -Property $outputContext.Data.PSObject.Properties.Name

        if ([string]::IsNullOrWhiteSpace([string]$correlatedAccount.UsId)) {
            throw 'Correlated AFAS user is missing required identifier [Gebruiker/UsId]. Verify the AFAS GetConnector output.'
        }

        $deleteMode = [string]$actionContext.Configuration.DeleteMode

    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    # Process
    switch ($lifecycleProcess) {
        'DeleteAccount' {
            # Mandatory fields
            $fieldsToUpdate = [ordered]@{
                Nm   = [string]$correlatedAccount.Nm
                MtCd = 1 # Import without changing the block status
            }

            if ($actionContext.Origin -ne 'reconciliation') {
                foreach ($property in $actionContext.Data.PSObject.Properties) {
                    $fieldsToUpdate[$property.Name] = $property.Value
                }
            }

            # We can only support certain actions during reconciliation.
            if ($actionContext.Origin -eq 'reconciliation') {
                if ($deleteMode -in @('blockKeepGroupsDisableOutSite', 'blockRemoveGroupsDisableOutSite')) {
                    # Clear email and upn
                    $fieldsToUpdate['EmAd'] = $null
                    $fieldsToUpdate['Upn'] = $null
                } else {
                    $fieldsToUpdate['Upn'] = $null
                }
            }

            if ($actionContext.Origin -eq 'reconciliation') {
                switch ($deleteMode) {
                    'blockKeepGroupsDisableOutSite' {
                        $fieldsToUpdate['Site'] = 'false'
                        $fieldsToUpdate['MtCd'] = 2
                        break
                    }
                    'blockRemoveGroupsDisableOutSite' {
                        $fieldsToUpdate['Site'] = 'false'
                        $fieldsToUpdate['MtCd'] = 0
                        break
                    }
                    'enableOutSiteNoBlock' {
                        $fieldsToUpdate['Site'] = 'true'
                        break
                    }
                    default {
                        throw "Unsupported DeleteMode value [$deleteMode]"
                    }
                }
            }

            $updateAccount = [PSCustomObject]@{
                KnUser = @{
                    Element = @{
                        '@UsId' = $correlatedAccount.UsId
                        Fields  = $fieldsToUpdate
                    }
                }
            }

            $body = ($updateAccount | ConvertTo-Json -Depth 10)
            $fieldsInPayload = ($actionContext.Data.PSObject.Properties.Name | ForEach-Object { [string]$_ }) -join ', '
            $splatUpdateParams = @{
                Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.UpdateConnector)"
                Headers         = $headers
                Method          = 'PUT'
                Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                ContentType     = 'application/json;charset=utf-8'
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
            }
            
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Deleting AFAS Profit account with accountReference: [$($actionContext.References.Account)]. Fields in update: [$fieldsInPayload]"
                $null = Invoke-RestMethod @splatUpdateParams -Verbose:$false
                $auditLogMessage = "Delete AFAS Profit account with accountReference: [$($actionContext.References.Account)] was successful. Account property(s) updated: [$fieldsInPayload]. Action initiated by: [$($actionContext.Origin)]"
            }
            else {
                Write-Information "[DryRun] Delete AFAS Profit account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement. Fields in update: [$fieldsInPayload]"
                $auditLogMessage = "[DryRun] Would delete AFAS Profit account with accountReference: [$($actionContext.References.Account)]. Account property(s) to update: [$fieldsInPayload]. Action initiated by: [$($actionContext.Origin)]"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $auditLogMessage
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "AFAS Profit account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "AFAS Profit account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
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
        $auditLogMessage = "Could not delete AFAS Profit account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage). Action initiated by: [$($actionContext.Origin)]"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not delete AFAS Profit account: [$($actionContext.References.Account)]. Error: $($_.Exception.Message). Action initiated by: [$($actionContext.Origin)]"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}