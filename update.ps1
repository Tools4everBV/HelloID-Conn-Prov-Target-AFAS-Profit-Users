#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Update
# PowerShell V2
#####################################################

# Set to false at start, at the end, only when no error occurs it is set to true
$outputContext.Success = $false 

# AccountReference must have a value for dryRun
$aRef = $actionContext.References.Account

# Set debug logging
switch ($($actionContext.Configuration.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}

function Resolve-AFASErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        try {
            $errorObjectConverted = $ErrorObject | ConvertFrom-Json -ErrorAction Stop

            if ($null -ne $errorObjectConverted.externalMessage) {
                $errorMessage = $errorObjectConverted.externalMessage
            }
            else {
                $errorMessage = $errorObjectConverted
            }
        }
        catch {
            $errorMessage = "$($ErrorObject.Exception.Message)"
        }

        Write-Output $errorMessage
    }
}

function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        if ( $($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $httpErrorObject = Resolve-HTTPError -ErrorObject $ErrorObject
            
            if (-not[String]::IsNullOrEmpty($httpErrorObject.ErrorMessage)) {
                $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage
                $errorMessage.AuditErrorMessage = Resolve-AFASErrorMessage -ErrorObject $httpErrorObject.ErrorMessage
            }
            else {
                $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
                $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
            }
        }
        
        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {
            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {
            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $errorMessage
    }
}
#endregion functions

try {
    # Correlation values
    $correlationProperty = "Gebruiker" # Has to match the name of the unique identifier
    $correlationValue = $actionContext.References.Account.Gebruiker # Has to match the value of the unique identifier

    $account = $actionContext.Data

    # Remove field because only used for export data or to set correlation
    if ($account.PSObject.Properties.Name -Contains 'Gebruiker') {
        $account.PSObject.Properties.Remove('Gebruiker')
    }
    if ($account.PSObject.Properties.Name -Contains 'Medewerker') {
        $account.PSObject.Properties.Remove('Medewerker')
    }

    $updateAccountFields = @()
    if ($account.PSObject.Properties.Name -Contains 'EmAd') {
        $updateAccountFields += "EmAd"
    }
    if ($account.PSObject.Properties.Name -Contains 'Upn') {
        $updateAccountFields += "Upn"
    }
    if (($account.PSObject.Properties.Name -Contains 'Site') -and ($actionContext.AccountCorrelated -eq $true)) {
        $updateAccountFields += "Site"
    }
    if (($account.PSObject.Properties.Name -Contains 'InSi') -and ($actionContext.AccountCorrelated -eq $true)) {
        $updateAccountFields += "InSi"
    }
    if (($actionContext.Configuration.updateUserId -eq $true) -and ($actionContext.AccountCorrelated -eq $true)) {
        $updateAccountFields += "UsId"
    }

    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = "UpdateAccount"
            Message = "The account reference could not be found"
            IsError = $true
        })
        
        throw 'The account reference could not be found'
    }

    if (($actionContext.Configuration.onlyUpdateOnCorrelate -eq $false) -or ($actionContext.AccountCorrelated -eq $true)) {
        # Get current account and verify if there are changes
        try {
            Write-Verbose "Querying AFAS user where [$($correlationProperty)] = [$($correlationValue)]"

            # Create authorization headers
            $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($($actionContext.Configuration.Token)))
            $authValue = "AfasToken $encodedToken"
            $Headers = @{ Authorization = $authValue }
            $Headers.Add("IntegrationId", "45963_140664") # Fixed value - Tools4ever Partner Integration ID

            $splatWebRequest = @{
                Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.GetConnector)?filterfieldids=$($correlationProperty)&filtervalues=$($correlationValue)&operatortypes=1"
                Headers         = $headers
                Method          = 'GET'
                ContentType     = "application/json;charset=utf-8"
                UseBasicParsing = $true
            }
            $currentAccount = (Invoke-RestMethod @splatWebRequest -Verbose:$false).rows

            if ($null -eq $currentAccount.Gebruiker) {
                throw "No AFAS user found where [$($correlationProperty)] = [$($correlationValue)]"
            }
            else {
                if ($actionContext.AccountCorrelated -eq $true) {
                    # Create previous account object to compare current data with specified account data
                    $previousAccount = [PSCustomObject]@{
                        # E-mail
                        'EmAd' = $currentAccount.Email_werk_gebruiker
                        # UPN
                        'Upn'  = $currentAccount.UPN
                        # Outsite
                        "Site" = [String]$currentAccount.OutSite
                        # InSite
                        "InSi" = [String]$currentAccount.InSite
                    }
                    if ($actionContext.Configuration.updateUserId -eq $true) {
                        $previousAccount | Add-Member -MemberType NoteProperty -Name 'UsId' -Value $($currentAccount.Gebruiker) -Force
                    }
                }
                else {
                    # Create previous account object to compare current data with specified account data
                    $previousAccount = [PSCustomObject]@{
                        # E-mail
                        'EmAd' = $currentAccount.Email_werk_gebruiker
                        # UPN
                        'Upn'  = $currentAccount.UPN
                    }
                }

                # Calculate changes between current data and provided data
                $splatCompareProperties = @{
                    ReferenceObject  = @($previousAccount.PSObject.Properties | Where-Object { $_.Name -in $updateAccountFields }) # Only select the properties to update
                    DifferenceObject = @($account.PSObject.Properties | Where-Object { $_.Name -in $updateAccountFields }) # Only select the properties to update
                }
                $changedProperties = $null
                $changedProperties = (Compare-Object @splatCompareProperties -PassThru)
                $oldProperties = $changedProperties.Where( { $_.SideIndicator -eq '<=' })
                $newProperties = $changedProperties.Where( { $_.SideIndicator -eq '=>' })

                if (($newProperties | Measure-Object).Count -ge 1) {
                    Write-Verbose "Changed properties: $($changedProperties | ConvertTo-Json)"

                    $updateAction = 'Update'
                }
                else {
                    Write-Verbose "No changed properties"

                    $updateAction = 'NoChanges'
                }
            }
        }
        catch {
            $ex = $PSItem
            $errorMessage = Get-ErrorMessage -ErrorObject $ex

            Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "UpdateAccount"
                    Message = "Error querying AFAS user where [$($correlationProperty)] = [$($correlationValue)]. Error Message: $($errorMessage.AuditErrorMessage)"
                    IsError = $true
                })
        
            # Skip further actions, as this is a critical error
            throw "Error querying AFAS user"
        }
        switch ($updateAction) {
            'Update' {
                # Execute initial update after account correlation
                if ($actionContext.Configuration.updateUserId -eq $true -and 'UsId' -in $changedProperties.Name -and $actionContext.AccountCorrelated -eq $true) {
                    # Update AFAS UserID
                    try {
                        # Create custom object with old and new values
                        $changedPropertiesObject = [PSCustomObject]@{
                            OldValues = @{}
                            NewValues = @{}
                        }

                        # Add the old properties to the custom object with old and new values - Only UsId as this is a seperate action only for UsId
                        foreach ($oldProperty in ($oldProperties | Where-Object { $_.Name -eq 'UsId' -and $_.Name -in $newProperties.Name })) {
                            $changedPropertiesObject.OldValues.$($oldProperty.Name) = $oldProperty.Value
                        }

                        # Add the new properties to the custom object with old and new values - Only UsId as this is a seperate action only for UsId
                        foreach ($newProperty in $newProperties | Where-Object { $_.Name -eq 'UsId' }) {
                            $changedPropertiesObject.NewValues.$($newProperty.Name) = $newProperty.Value
                        }
                        Write-Verbose "Changed properties: $($changedPropertiesObject | ConvertTo-Json)"
                        # Create custom account object for update and set with default properties and values
                        $updateAccountUserId = [PSCustomObject]@{
                            'KnUser' = @{
                                'Element' = @{
                                    # Gebruiker
                                    '@UsId'  = $currentAccount.Gebruiker
                                    'Fields' = @{
                                        # Mutatie code
                                        'MtCd'    = 4
                                        # Omschrijving
                                        "Nm"      = $currentAccount.DisplayName

                                        # Nieuwe gebruikerscode
                                        "UsIdNew" = $($account.'UsId')
                                    }
                                }
                            }
                        }

                        $body = ($updateAccountUserId | ConvertTo-Json -Depth 10)
                        $splatWebRequest = @{
                            Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.UpdateConnector)"
                            Headers         = $headers
                            Method          = 'PUT'
                            Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                            ContentType     = "application/json;charset=utf-8"
                            UseBasicParsing = $true
                        }
                        if (-Not($actionContext.DryRun -eq $true)) {
                            Write-Verbose "Updating UserId for AFAS user [$($currentAccount.Gebruiker)]. Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"

                            $updatedAccountUserId = Invoke-RestMethod @splatWebRequest -Verbose:$false
                            $outputContext.AuditLogs.Add([PSCustomObject]@{
                                    Action  = "UpdateAccount"
                                    Message = "Successfully updated UserId for AFAS user [$($currentAccount.Gebruiker)]. Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"
                                    IsError = $false
                                })
                        }
                        else {
                            Write-Warning "DryRun: Would update UserId for AFAS user [$($currentAccount.Gebruiker)]. Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"
                        }

                        $correlationValue = $account.'UsId'

                        # Get Account data to make sure we have the latest data (after update of UserId)
                        $splatWebRequest = @{
                            Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.GetConnector)?filterfieldids=$($correlationProperty)&filtervalues=$($correlationValue)&operatortypes=1"
                            Headers         = $headers
                            Method          = 'GET'
                            ContentType     = "application/json;charset=utf-8"
                            UseBasicParsing = $true
                        }
                        $currentAccount = (Invoke-RestMethod @splatWebRequest -Verbose:$false).rows

                        $aRef = [PSCustomObject]@{
                            Gebruiker = $currentAccount.Gebruiker
                        }
                        $outputContext.AccountReference = $aRef

                        
                    }
                    catch {
                        $ex = $PSItem
                        $errorMessage = Get-ErrorMessage -ErrorObject $ex
                
                        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"
            
                        $outputContext.AuditLogs.Add([PSCustomObject]@{
                                Action  = "UpdateAccount"
                                Message = "Error updating UserId for AFAS user [$($currentAccount.Gebruiker)]. Error Message: $($errorMessage.AuditErrorMessage). Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"
                                IsError = $true
                            })

                        # Skip further actions, as this is a critical error
                        throw "Error updating UserId of AFAS user"
                    }                         
                }
                # Update AFAS User
                try {
                    # Create custom object with old and new values
                    $changedPropertiesObject = [PSCustomObject]@{
                        OldValues = @{}
                        NewValues = @{}
                    }

                    # Add the old properties to the custom object with old and new values
                    foreach ($oldProperty in ($oldProperties | Where-Object { $_.Name -in $newProperties.Name })) {
                        $changedPropertiesObject.OldValues.$($oldProperty.Name) = $oldProperty.Value
                    }

                    # Add the new properties to the custom object with old and new values
                    foreach ($newProperty in $newProperties) {
                        $changedPropertiesObject.NewValues.$($newProperty.Name) = $newProperty.Value
                    }
                    Write-Verbose "Changed properties: $($changedPropertiesObject | ConvertTo-Json)"

                    # Create custom account object for update and set with default properties and values
                    $updateAccount = [PSCustomObject]@{
                        'KnUser' = @{
                            'Element' = @{
                                # Gebruiker
                                '@UsId'  = $currentAccount.Gebruiker
                                'Fields' = @{
                                    # Mutatie code
                                    'MtCd' = $account.MtCd
                                    # Omschrijving
                                    "Nm"   = $currentAccount.DisplayName
                                }
                            }
                        }
                    }

                    # Add the updated properties to the custom account object for update
                    foreach ($newProperty in $newProperties) {
                        $updateAccount.KnUser.Element.Fields.$($newProperty.Name) = $newProperty.Value
                    }

                    $body = ($updateAccount | ConvertTo-Json -Depth 10)
                    $splatWebRequest = @{
                        Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.UpdateConnector)"
                        Headers         = $headers
                        Method          = 'PUT'
                        Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                        ContentType     = "application/json;charset=utf-8"
                        UseBasicParsing = $true
                    }

                    if (-Not($actionContext.DryRun -eq $true)) {
                        Write-Verbose "Updating AFAS user [$($currentAccount.Gebruiker)]. Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"
                            
                        $updatedAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false

                        $outputContext.AuditLogs.Add([PSCustomObject]@{
                                Action  = "UpdateAccount"
                                Message = "Successfully updated AFAS user [$($currentAccount.Gebruiker)]. Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"
                                IsError = $false
                            })
                    }
                    else {
                        Write-Warning "DryRun: Would update AFAS user [$($currentAccount.Gebruiker)]. Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"
                    }
                }
                catch {
                    $ex = $PSItem
                    $errorMessage = Get-ErrorMessage -ErrorObject $ex
                    
                    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"
                
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = "UpdateAccount"
                            Message = "Error updating AFAS user [$($currentAccount.Gebruiker)]. Error Message: $($errorMessage.AuditErrorMessage)."
                            IsError = $true
                        })
                    # Skip further actions, as this is a critical error
                    throw "Error updating AFAS user"
                }

                break
            }
            'NoChanges' {
                Write-Verbose "No changes needed for AFAS user [$($currentAccount.Gebruiker)]"
                break
            }
        }
    }
    else {
        $previousAccount = $account
        Write-Verbose "The configuration parameter only update on correlate is [$($actionContext.Configuration.onlyUpdateOnCorrelate)]"
    }
}
catch {
    $ex = $PSItem
    Write-Verbose "ERROR: $ex"
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($outputContext.AuditLogs.IsError -contains $true)) {
        $outputContext.Success = $true
    }

    # Define ExportData with account fields and correlation property 
    $exportData = $account.PsObject.Copy()
    # Add correlation property to exportdata
    $exportData | Add-Member -MemberType NoteProperty -Name $correlationProperty -Value $correlationValue -Force
    # Add aRef properties to exportdata
    foreach ($aRefProperty in $aRef.PSObject.Properties) {
        $exportData | Add-Member -MemberType NoteProperty -Name $aRefProperty.Name -Value $aRefProperty.Value -Force
    }
    $outputContext.Data = $exportData
    $outputContext.PreviousData = $previousAccount
}