#################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Update
# PowerShell V2
#################################################

#TODO: Remove hardcoded values
# $actionContext.References.Account = "45963.AndreO"
# $actionContext.Configuration.UpdateUserId = $true
# $actionContext.AccountCorrelated = $true
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

function Invoke-AFASUserUpdate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $CurrentUsId,

        [Parameter(Mandatory)]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [object]
        $FieldsToUpdate,

        [Parameter(Mandatory)]
        [string]
        $AccountReference
    )

    if (-not $FieldsToUpdate.Contains('Nm')) {
        $FieldsToUpdate['Nm'] = $Name
    }

    $updateAccount = [PSCustomObject]@{
        KnUser = @{
            Element = @{
                '@UsId' = $CurrentUsId
                Fields  = $FieldsToUpdate
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

    Write-Information "Updating AFAS Profit account with accountReference: [$AccountReference]"
    $null = Invoke-RestMethod @splatUpdateParams -Verbose:$false
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

    $lifecycleActionList = @()
    $updateUserIdEnabled = [bool]$actionContext.Configuration.UpdateUserId
    $newUsId = $null
    $currentUsId = $null
    $accountPropertiesChanged = @()
    if ($correlatedAccount.Count -eq 1) {
        $correlatedAccount = $correlatedAccount[0]
        $outputContext.AccountReference = [string]$correlatedAccount.BcCo
        $currentUsId = [string]$correlatedAccount.UsId

        $outputContext.PreviousData = $correlatedAccount | Select-Object -Property $outputContext.Data.PSObject.Properties.Name
        
        $mappedProperties = @($actionContext.Data.PSObject.Properties | ForEach-Object {
                if ($_.Value -is [string] -and $_.Value -eq '') { $_.Value = $null }
                if ($_.Value -is [string] -and $_.Value -eq "false") { $_.Value = $false }
                if ($_.Value -is [string] -and $_.Value -eq "true") { $_.Value = $true }
                $_
            }
        )

        # Only use mapped UsId when explicit UpdateUserId is enabled.
        if (-not $updateUserIdEnabled) {
            $mappedProperties = @($mappedProperties | Where-Object { $_.Name -ne 'UsId' })
        }

        # Always compare the account against the current account in target system
        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties)
            DifferenceObject = $mappedProperties
        }
        $propertiesChanged = @(Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' })

        $usIdChange = @($propertiesChanged | Where-Object { $_.Name -eq 'UsId' })
        $accountPropertiesChanged = @($propertiesChanged | Where-Object { $_.Name -ne 'UsId' })

        # Depending on connector configuration, allow changes of the User ID (UsId).
        if ($updateUserIdEnabled -and $usIdChange.Count -gt 0 -and $actionContext.AccountCorrelated) {
            $newUsId = [string]($usIdChange | Select-Object -First 1 -ExpandProperty Value)
            $lifecycleActionList += @('UpdateUserId')
        }
        # Keep UsId in output data aligned with the current AFAS value when it exists in mapping.
        elseif ($outputContext.Data.PSObject.Properties.Name -contains 'UsId') {
            $outputContext.Data.UsId = $correlatedAccount.UsId
        }

        if ($accountPropertiesChanged.Count -gt 0) {
            $lifecycleActionList += @('UpdateAccount')
        }

        if ($lifecycleActionList.Count -eq 0) {
            $lifecycleActionList += @('NoChanges')
        }
    }
    else {
        $lifecycleActionList += @('NotFound')
    }

    # Process
    foreach ($action in $lifecycleActionList) {
        switch ($action) {
            'UpdateUserId' {
                Write-Information "Account property(s) required to update: UsId"
                $previousUsId = $currentUsId

                # Default body for update.
                $fieldsToUpdate = [ordered]@{
                    MtCd    = 4
                    UsIdNew = $newUsId
                }

                if (-not($actionContext.DryRun -eq $true)) {
                    Invoke-AFASUserUpdate -CurrentUsId $currentUsId -Name $correlatedAccount.Nm -FieldsToUpdate $fieldsToUpdate -AccountReference $actionContext.References.Account
                }
                else {
                    Write-Information "[DryRun] Update AFAS Profit account UsId with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
                }

                # If UsId was changed, next actions in this run must target the new UsId.
                $currentUsId = $newUsId
                if ($outputContext.Data.PSObject.Properties.Name -contains 'UsId') {
                    $outputContext.Data.UsId = $newUsId
                }

                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Update account was successful, Account [UsId: $($previousUsId)] updated to [UsId: $($newUsId)]"
                        IsError = $false
                    })
                break
            }

            'UpdateAccount' {
                Write-Information "Account property(s) required to update: $($accountPropertiesChanged.Name -join ', ')"

                # Default body for update.
                $fieldsToUpdate = [ordered]@{
                    MtCd = 1
                }

                # Add changed properties to Fields payload.
                foreach ($property in $accountPropertiesChanged) {
                    $fieldsToUpdate[$property.Name] = $property.Value
                }

                if (-not($actionContext.DryRun -eq $true)) {
                    Invoke-AFASUserUpdate -CurrentUsId $currentUsId -Name $correlatedAccount.Nm -FieldsToUpdate $fieldsToUpdate -AccountReference $actionContext.References.Account
                }
                else {
                    Write-Information "[DryRun] Update AFAS Profit account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
                }

                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Update account was successful, Account property(s) updated: [$($accountPropertiesChanged.Name -join ',')]"
                        IsError = $false
                    })
                break
            }

            'NoChanges' {
                Write-Information "No changes to AFAS Profit account with accountReference: [$($actionContext.References.Account)]"

                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Skipped updating AFAS Profit account with accountReference: [$($actionContext.References.Account)]. Reason: No changes."
                        IsError = $false
                    })
                break
            }

            'NotFound' {
                Write-Information "AFAS Profit account with accountReference: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"

                $outputContext.Success = $false
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "AFAS Profit account with accountReference: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                        IsError = $true
                    })
                break
            }
        }
    }
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem

    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-AFAS-ProfitError -ErrorObject $ex
        $auditLogMessage = "Could not update AFAS-Profit account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not update AFAS-Profit account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}
