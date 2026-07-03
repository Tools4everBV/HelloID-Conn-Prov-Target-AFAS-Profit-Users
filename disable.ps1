#################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Disable
# PowerShell V2
#################################################

#TODO: Remove hardcoded values
$actionContext.References.Account = "1000525"
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
        Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.GetConnector)?filterfieldids=Persoonsnummer&filtervalues=$([uri]::EscapeDataString($actionContext.References.Account))&operatortypes=1"
        Headers         = $headers
        Method          = 'GET'
        ContentType     = 'application/json;charset=utf-8'
        UseBasicParsing = $true
        ErrorAction     = 'Stop'
    }

    $correlatedAccount = (Invoke-RestMethod @splatQueryParams).rows

    if (($correlatedAccount | Measure-Object).Count -eq 1) {
        $lifecycleProcess = 'DisableAccount'

        if ([string]::IsNullOrWhiteSpace([string]$correlatedAccount.UsId)) {
            throw 'Correlated AFAS user is missing required identifier [Gebruiker/UsId]. Verify the AFAS GetConnector output.'
        }
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    # Process
    switch ($lifecycleProcess) {
        'DisableAccount' {
            # Mandatory fields
            $fieldsToUpdate = [ordered]@{
                Nm   = [string]$correlatedAccount.Nm
                MtCd = 1 # Import without changing the block status
            }

            $lifecycleActions = @('DisableInsite')
            
            if ($correlatedAccount.Awin) {
                $lifecycleActions += 'DisableProfitWindows'
                $fieldsToUpdate['Awin'] = 'false'
            }

            $disableDeleteMode = [string]$actionContext.Configuration.DisableDeleteMode
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
                Write-Information "Disabling AFAS Profit account with accountReference: [$($actionContext.References.Account)]"
                $null = Invoke-RestMethod @splatUpdateParams -Verbose:$false
                $auditLogMessage = "Disabled AFAS Profit account with accountReference: [$($actionContext.References.Account)] using actions [$($lifecycleActions -join ', ')]"
            }
            else {
                Write-Information "[DryRun] Disable AFAS Profit account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement using actions [$($lifecycleActions -join ', ')]"
                $auditLogMessage = "[DryRun] Would disable AFAS Profit account with accountReference: [$($actionContext.References.Account)] using actions [$($lifecycleActions -join ', ')]"
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
                    Message = "AFAS Profit account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $false
                })
            break
        }
    }
    
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem

    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-AFAS-ProfitError -ErrorObject $ex
        $auditLogMessage = "Could not disable AFAS-Profit account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not disable AFAS-Profit account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}
