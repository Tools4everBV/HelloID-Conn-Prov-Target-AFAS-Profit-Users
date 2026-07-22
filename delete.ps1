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
        Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.GetConnector)?filterfieldids=UsId&filtervalues=$([uri]::EscapeDataString($actionContext.References.Account))&operatortypes=1"
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
        elseif ($correlatedAccount.Awin -or $correlatedAccount.OcUs -or $correlatedAccount.PoMa -or $correlatedAccount.AcUs) {
            throw 'Correlated AFAS user has active permissions preventing InSite access from being disabled.'
        }

        $disableDeleteMode = [string]$actionContext.Configuration.DisableDeleteMode

        # Lifecycle actions are evaluated first and merged into one API-call.
        $lifecycleActions = @(
            'DisableInsite'
        )

        # Only include UpdateAccount action when there are data changes and not in reconciliation (where data is unavailable).
        $propertiesChanged = $null
        if ($actionContext.Origin -ne 'reconciliation') {
            $splatCompareProperties = @{
                ReferenceObject  = @($correlatedAccount.PSObject.Properties)
                DifferenceObject = @(
                    $actionContext.Data.PSObject.Properties | ForEach-Object {
                        if ($_.Value -is [string] -and $_.Value -eq '') { $_.Value = $null }
                        if ($_.Value -is [string] -and $_.Value -eq "false") { $_.Value = $false }
                        if ($_.Value -is [string] -and $_.Value -eq "true") { $_.Value = $true }
                        $_
                    }
                )
            }
            $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }

            if ($propertiesChanged) {
                $lifecycleActions = @('UpdateAccount') + $lifecycleActions
            }
        }
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

            # We can only support certain actions during reconciliation.
            if ($actionContext.Origin -eq 'reconciliation') {                
                if ($disableDeleteMode -in @('blockKeepGroupsDisableOutSite', 'blockRemoveGroupsDisableOutSite')) {
                    # Clear email and upn so OutSite can be disabled
                    $fieldsToUpdate['Upn'] = $null
                    $fieldsToUpdate['EmAd'] = $null
                }
                else {
                    throw 'Reconciliation is not supported for Delete action where OutSite needs to stay enabled. Please reconcile the account manually in AFAS Profit.'
                }
            } #TODO: Repurpose configuration.json options for reconciliation only since there is no fieldmapping. For the non-reconciliation scenario, the fieldmapping is used to determine which fields are updated. If Outsite stays enabled, then Upn and EmAd can become "accountReference@domain.com"

            switch ($disableDeleteMode) {
                'blockKeepGroupsDisableOutSite' {
                    $lifecycleActions += 'DisableOutsite'
                    $lifecycleActions += 'BlockUserKeepGroups'
                    $fieldsToUpdate['Site'] = 'false'
                    $fieldsToUpdate['MtCd'] = 2
                    break
                }
                'blockRemoveGroupsDisableOutSite' {
                    $lifecycleActions += 'DisableOutsite'
                    $lifecycleActions += 'BlockUserRemoveGroups'
                    $fieldsToUpdate['Site'] = 'false'
                    $fieldsToUpdate['MtCd'] = 0
                    break
                }
                'enableOutSiteNoBlock' {
                    $lifecycleActions += 'EnableOutsite'
                    $fieldsToUpdate['Site'] = 'true'
                    break
                }
                default {
                    throw "Unsupported DisableDeleteMode value [$disableDeleteMode]"
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
                Write-Information "Deleting AFAS Profit account with accountReference: [$($actionContext.References.Account)]"
                $null = Invoke-RestMethod @splatUpdateParams -Verbose:$false
                $auditLogMessage = "Delete AFAS Profit account with accountReference: [$($actionContext.References.Account)] was successful using actions [$($lifecycleActions -join ', ')]. Action initiated by: [$($actionContext.Origin)]"
            }
            else {
                Write-Information "[DryRun] Delete AFAS Profit account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement using actions [$($lifecycleActions -join ', ')]"
                $auditLogMessage = "[DryRun] Would delete AFAS Profit account with accountReference: [$($actionContext.References.Account)] using actions [$($lifecycleActions -join ', ')]. Action initiated by: [$($actionContext.Origin)]"
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