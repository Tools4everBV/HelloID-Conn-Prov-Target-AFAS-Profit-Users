#################################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-RevokePermission
# PowerShell V2
#################################################################

#TODO: Remove hardcoded values
# $actionContext.References.Account = "45963.AndreO"
# $actionContext.DryRun = $false

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

# Begin
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
    $permissionReference = [string]$actionContext.References.Permission.Reference

    if ($correlatedAccount.Count -eq 1) {
        $correlatedAccount = $correlatedAccount[0]
        if ([string]::IsNullOrWhiteSpace([string]$correlatedAccount.UsId)) {
            throw 'Correlated AFAS user is missing required identifier [Gebruiker/UsId]. Verify the AFAS GetConnector output.'
        }
        elseif ($correlatedAccount.$permissionReference -eq $true) {
            $lifecycleProcess = 'RevokePermission'
        }
        else {
            $lifecycleProcess = 'AlreadyRevoked'
        }

    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    # Process
    switch ($lifecycleProcess) {
        'RevokePermission' {

            # Mandatory fields
            $fieldsToUpdate = [ordered]@{
                Nm   = [string]$correlatedAccount.Nm
                MtCd = 1 # Import without changing the block status
            }
            $fieldsToUpdate[$permissionReference] = 'false'

            # AFAS dependency: InSi cannot be disabled while Profit Windows is still active.
            if ($permissionReference -eq 'InSi' -and [bool]$correlatedAccount.Awin) {
                $fieldsToUpdate['Awin'] = 'false'
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
                Write-Information "Revoking AFAS Profit permission: [$($actionContext.PermissionDisplayName)] - [$permissionReference]"
                $null = Invoke-RestMethod @splatUpdateParams -Verbose:$false

                if ($permissionReference -eq 'InSi' -and [bool]$correlatedAccount.Awin) {
                    $auditLogMessage = "Revoked permission [$($actionContext.PermissionDisplayName)] and disabled dependent permission [Awin]. Action initiated by: [$($actionContext.Origin)]"
                }
                else {
                    $auditLogMessage = "Revoked permission [$($actionContext.PermissionDisplayName)]. Action initiated by: [$($actionContext.Origin)]"
                }
            }
            else {
                Write-Information "[DryRun] Revoke AFAS Profit permission: [$($actionContext.PermissionDisplayName)] - [$permissionReference], will be executed during enforcement"
                if ($permissionReference -eq 'InSi' -and [bool]$correlatedAccount.Awin) {
                    $auditLogMessage = "[DryRun] Would revoke permission [$($actionContext.PermissionDisplayName)] and disable dependent permission [Awin]. Action initiated by: [$($actionContext.Origin)]"
                }
                else {
                    $auditLogMessage = "[DryRun] Would revoke permission [$($actionContext.PermissionDisplayName)]. Action initiated by: [$($actionContext.Origin)]"
                }
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $auditLogMessage
                    IsError = $false
                })
            break
        }

        'AlreadyRevoked' {
            Write-Information "AFAS Profit permission: [$($actionContext.PermissionDisplayName)] - [$permissionReference] is already revoked for account: [$($actionContext.References.Account)]"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "AFAS Profit permission: [$($actionContext.PermissionDisplayName)] - [$permissionReference] is already revoked for account: [$($actionContext.References.Account)]. Action initiated by: [$($actionContext.Origin)]"
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
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-AFASProfitError -ErrorObject $ex
        $auditLogMessage = "Could not revoke AFAS Profit permission for account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage). Action initiated by: [$($actionContext.Origin)]"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not revoke AFAS Profit permission for account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message). Action initiated by: [$($actionContext.Origin)]"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}