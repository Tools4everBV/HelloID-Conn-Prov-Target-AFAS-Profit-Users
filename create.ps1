#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Create
#
# Version: 2.1.0
#####################################################
# Initialize default values
$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false # Set to false at start, at the end, only when no error occurs it is set to true
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = "Continue" }
    $false { $VerbosePreference = "SilentlyContinue" }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Correlation values
$correlationProperty = "Medewerker" # Has to match the name of the unique identifier
$correlationValue = $p.externalId # Has to match the value of the unique identifier

#Change mapping here
$userId = "12345.$($p.ExternalId)"
# Shorten userId to max 20 chars.
$userId = $userId.substring(0, [System.Math]::Min(20, $userId.Length))
$account = [PSCustomObject]@{
    # Gebruiker code
    'UsId' = $userId
    # Mutatie code
    'MtCd' = 1
    # Omschrijving
    "Nm"   = $p.DisplayName # Only used for new users, for existing users, the current displayname of the AFAS user is used
    # E-mail
    'EmAd' = $p.Accounts.MicrosoftActiveDirectory.mail
    # UPN - Vulling UPN afstemmen met AFAS beheer
    'Upn'  = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName
    # Wachtwoord
    "Pw"   = "GHJKL!!!23456gfdgf" # dummy pwd, not used, but required

    # Set properties below to false (only on create), otherwise some will be set to true by default when not provided in account object
    # Outsite
    "Site" = $false
    # InSite
    "InSi" = $false
    
    # Profit Windows
    "Awin" = $false
    # Connector
    "Acon" = $false
    # Reservekopieen via commandline
    "Abac" = $false
    # Commandline
    "Acom" = $false

    # Meewerklicentie actieveren
    "OcUs" = $false
    # AFAS Online Portal-beheerder
    "PoMa" = $false
    # AFAS Accept
    "AcUs" = $false
}

# Define account properties to update
$updateAccountFields = @("EmAd", "Upn") #@("UsId", "EmAd", "Upn")
if ($c.updateUserId -eq $true) {
    $updateAccountFields += "UsId"
}

# Define account properties to store in account data
$storeAccountFields = @("UsId", "EmAd", "Upn")

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
            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject

            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage

            $errorMessage.AuditErrorMessage = Resolve-AFASErrorMessage -ErrorObject $httpErrorObject.ErrorMessage
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
    # Get current account and verify if the action should be either [updated and correlated] or just [correlated]
    try {
        Write-Verbose "Querying AFAS user where [$($correlationProperty)] = [$($correlationValue)]"

        # Create authorization headers
        $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($($c.Token)))
        $authValue = "AfasToken $encodedToken"
        $Headers = @{ Authorization = $authValue }
        $Headers.Add("IntegrationId", "45963_140664") # Fixed value - Tools4ever Partner Integration ID

        $splatWebRequest = @{
            Uri             = "$($c.BaseUri)/connectors/$($c.GetConnector)?filterfieldids=$($correlationProperty)&filtervalues=$($correlationValue)&operatortypes=1"
            Headers         = $headers
            Method          = 'GET'
            ContentType     = "application/json;charset=utf-8"
            UseBasicParsing = $true
        }
        $currentAccount = (Invoke-RestMethod @splatWebRequest -Verbose:$false).rows

        if ($null -eq $currentAccount.Gebruiker) {
            if ($($c.createAccount) -eq $true) {
                Write-Verbose "No AFAS user found where [$($correlationProperty)] = [$($correlationValue)]. Creating new user"
                $action = 'Create'
            }
            else {
                throw "No AFAS user found where [$($correlationProperty)] = [$($correlationValue)] and [create user when not found in AFAS] set to [$($c.createAccount)]"
            }
        }
        else {
            # Create previous account object to compare current data with specified account data
            $previousAccount = [PSCustomObject]@{
                # Gebruiker code
                'UsId' = $currentAccount.Gebruiker
                # E-mail
                'EmAd' = $currentAccount.Email_werk_gebruiker
                # UPN
                'Upn'  = $currentAccount.UPN
            }

            if ($($c.updateOnCorrelate) -eq $true) {
                $action = 'Update'

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
            else {
                $action = 'Correlate'
            }
        }
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        $auditLogs.Add([PSCustomObject]@{
                # Action  = "" # Optional
                Message = "Error querying AFAS user where [$($correlationProperty)] = [$($correlationValue)]. Error Message: $($errorMessage.AuditErrorMessage)"
                IsError = $true
            })
        
        # Skip further actions, as this is a critical error
        continue
    }

    # Either [create], [update and correlate] or just [correlate]
    switch ($action) {
        'Create' {
            # Create AFAS User
            try {
                # Create custom account object for create and set with default properties and values
                $createAccount = [PSCustomObject]@{
                    'KnUser' = @{
                        'Element' = @{
                            # Gebruiker
                            '@UsId'  = $account.UsId
                            'Fields' = @{
                                # Nummer
                                'BcCo' = $currentAccount.Persoonsnummer
                            }
                        }
                    }
                }

                # Add all account properties to the custom account object for create - Except for UsId as it is set at a different level
                foreach ($accountProperty in $account.PSObject.Properties | Where-Object { $_.Name -ne 'UsId' }) {
                    $createAccount.KnUser.Element.Fields.$($accountProperty.Name) = $accountProperty.Value
                }

                $body = ($createAccount | ConvertTo-Json -Depth 10)
                $splatWebRequest = @{
                    Uri             = "$($c.BaseUri)/connectors/$($c.UpdateConnector)"
                    Headers         = $headers
                    Method          = 'PUT'
                    Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                    ContentType     = "application/json;charset=utf-8"
                    UseBasicParsing = $true
                }

                if (-not($dryRun -eq $true)) {
                    Write-Verbose "Creating AFAS user [$($account.UsId)]. Account object: $($createAccount | ConvertTo-Json -Depth 10)" 

                    $createdAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false

                    # Set aRef object for use in futher actions
                    $aRef = [PSCustomObject]@{
                        Gebruiker = $account.UsId
                    }

                    $auditLogs.Add([PSCustomObject]@{
                            # Action  = "" # Optional
                            Message = "Successfully created AFAS user [$($account.UsId)]"
                            IsError = $false
                        })
                }
                else {
                    Write-Warning "DryRun: Would create AFAS user [$($account.UsId)]. Account object: $($createAccount | ConvertTo-Json -Depth 10)"
                }
            }
            catch {
                $ex = $PSItem
                $errorMessage = Get-ErrorMessage -ErrorObject $ex
                        
                Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"
                    
                $auditLogs.Add([PSCustomObject]@{
                        # Action  = "" # Optional
                        Message = "Error creating AFAS user [$($account.UsId)]. Error Message: $($errorMessage.AuditErrorMessage). Account object: $($createAccount | ConvertTo-Json -Depth 10)"
                        IsError = $true
                    })
            }
            
            # Define ExportData with account fields and correlation property 
            $exportData = $account.PsObject.Copy() | Select-Object $storeAccountFields
            # Add correlation property to exportdata
            $exportData | Add-Member -MemberType NoteProperty -Name $correlationProperty -Value $correlationValue -Force
            # Add aRef properties to exportdata
            foreach ($aRefProperty in $aRef.PSObject.Properties) {
                $exportData | Add-Member -MemberType NoteProperty -Name $aRefProperty.Name -Value $aRefProperty.Value -Force
            }

            break
        }
        'Update' {       
            switch ($updateAction) {
                'Update' {
                    if ($c.updateUserId -eq $true -and 'UsId' -in $changedProperties.Name) {
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
                                Uri             = "$($c.BaseUri)/connectors/$($c.UpdateConnector)"
                                Headers         = $headers
                                Method          = 'PUT'
                                Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                                ContentType     = "application/json;charset=utf-8"
                                UseBasicParsing = $true
                            }
                                
                            if (-not($dryRun -eq $true)) {
                                Write-Verbose "Updating UserId for AFAS user [$($currentAccount.Gebruiker)]. Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"

                                $updatedAccountUserId = Invoke-RestMethod @splatWebRequest -Verbose:$false

                                $auditLogs.Add([PSCustomObject]@{
                                        # Action  = "" # Optional
                                        Message = "Successfully updated UserId for AFAS user [$($currentAccount.Gebruiker)]. Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"
                                        IsError = $false
                                    })
                            }
                            else {
                                Write-Warning "DryRun: Would update UserId for AFAS user [$($currentAccount.Gebruiker)]. Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"
                            }

                            # Get Account data to make sure we have the latest data (after update of UserId)
                            $splatWebRequest = @{
                                Uri             = "$($c.BaseUri)/connectors/$($c.GetConnector)?filterfieldids=$($correlationProperty)&filtervalues=$($correlationValue)&operatortypes=1"
                                Headers         = $headers
                                Method          = 'GET'
                                ContentType     = "application/json;charset=utf-8"
                                UseBasicParsing = $true
                            }
                            $currentAccount = (Invoke-RestMethod @splatWebRequest -Verbose:$false).rows
                        }
                        catch {
                            $ex = $PSItem
                            $errorMessage = Get-ErrorMessage -ErrorObject $ex
                        
                            Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"
                    
                            $auditLogs.Add([PSCustomObject]@{
                                    # Action  = "" # Optional
                                    Message = "Error updating UserId for AFAS user [$($currentAccount.Gebruiker)]. Error Message: $($errorMessage.AuditErrorMessage). Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"
                                    IsError = $true
                                })
                        }                         
                    }

                    # Update AFAS User
                    try {
                        # Create custom object with old and new values
                        $changedPropertiesObject = [PSCustomObject]@{
                            OldValues = @{}
                            NewValues = @{}
                        }

                        # Add the old properties to the custom object with old and new values - Except for UsId as it is updated with a seperate action
                        foreach ($oldProperty in ($oldProperties | Where-Object { $_.Name -ne 'UsId' -and $_.Name -in $newProperties.Name })) {
                            $changedPropertiesObject.OldValues.$($oldProperty.Name) = $oldProperty.Value
                        }

                        # Add the new properties to the custom object with old and new values - Except for UsId as it is updated with a seperate action
                        foreach ($newProperty in $newProperties | Where-Object { $_.Name -ne 'UsId' }) {
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

                        # Add the updated properties to the custom account object for update - Except for UsId as it is updated with a seperate action - Only add changed properties. AFAS will throw an error when trying to update this with the same value
                        foreach ($newProperty in $newProperties | Where-Object { $_.Name -ne 'UsId' }) {
                            $updateAccount.KnUser.Element.Fields.$($newProperty.Name) = $newProperty.Value
                        }

                        $body = ($updateAccount | ConvertTo-Json -Depth 10)
                        $splatWebRequest = @{
                            Uri             = "$($c.BaseUri)/connectors/$($c.UpdateConnector)"
                            Headers         = $headers
                            Method          = 'PUT'
                            Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                            ContentType     = "application/json;charset=utf-8"
                            UseBasicParsing = $true
                        }
    
                        if (-not($dryRun -eq $true)) {
                            Write-Verbose "Updating AFAS user [$($currentAccount.Gebruiker)]. Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"

                            $updatedAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false

                            # Set aRef object for use in futher actions
                            $aRef = [PSCustomObject]@{
                                Gebruiker = $currentAccount.Gebruiker
                            }
                            
                            $auditLogs.Add([PSCustomObject]@{
                                    # Action  = "" # Optional
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
                
                        $auditLogs.Add([PSCustomObject]@{
                                # Action  = "" # Optional
                                Message = "Error updating AFAS user [$($currentAccount.Gebruiker)]. Error Message: $($errorMessage.AuditErrorMessage). Old values: $($changedPropertiesObject.oldValues | ConvertTo-Json -Depth 10). New values: $($changedPropertiesObject.newValues | ConvertTo-Json -Depth 10)"
                                IsError = $true
                            })
                    }

                    break
                }
                'NoChanges' {
                    Write-Verbose "No changes needed for AFAS user [$($currentAccount.Gebruiker)]"

                    if (-not($dryRun -eq $true)) {
                        # Set aRef object for use in futher actions
                        $aRef = [PSCustomObject]@{
                            Gebruiker = $currentAccount.Gebruiker
                        }

                        $auditLogs.Add([PSCustomObject]@{
                                # Action  = "" # Optional
                                Message = "No changes needed for AFAS user [$($currentAccount.Gebruiker)]"
                                IsError = $false
                            })
                    }
                    else {
                        Write-Warning "DryRun: No changes needed for AFAS user [$($currentAccount.Gebruiker)]"
                    }                  

                    break
                }
            }
        
            # Define ExportData with account fields and correlation property 
            $exportData = $account.PsObject.Copy() | Select-Object $storeAccountFields
            # Add correlation property to exportdata
            $exportData | Add-Member -MemberType NoteProperty -Name $correlationProperty -Value $correlationValue -Force
            # Add aRef properties to exportdata
            foreach ($aRefProperty in $aRef.PSObject.Properties) {
                $exportData | Add-Member -MemberType NoteProperty -Name $aRefProperty.Name -Value $aRefProperty.Value -Force
            }
            
            break
        }
        'Correlate' {
            Write-Verbose "Correlating to AFAS user [$($currentAccount.Gebruiker)]"

            if (-not($dryRun -eq $true)) {
                # Set aRef object for use in futher actions
                $aRef = [PSCustomObject]@{
                    Gebruiker = $currentAccount.Gebruiker
                }

                $auditLogs.Add([PSCustomObject]@{
                        # Action  = "" # Optional
                        Message = "Successfully correlated to AFAS user [$($currentAccount.Gebruiker)]"
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would correlate to AFAS user [$($currentAccount.Gebruiker)]"
            }

            # Define ExportData with account fields and correlation property 
            $exportData = $account.PsObject.Copy() | Select-Object $storeAccountFields
            # Add correlation property to exportdata
            $exportData | Add-Member -MemberType NoteProperty -Name $correlationProperty -Value $correlationValue -Force
            # Add aRef properties to exportdata
            foreach ($aRefProperty in $aRef.PSObject.Properties) {
                $exportData | Add-Member -MemberType NoteProperty -Name $aRefProperty.Name -Value $aRefProperty.Value -Force
            }
            
            break
        }
    }
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($auditLogs.IsError -contains $true)) {
        $success = $true
    }
    
    # Send results
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $aRef
        AuditLogs        = $auditLogs
        PreviousAccount  = $previousAccount
        Account          = $account
    
        # Optionally return data for use in other systems
        ExportData       = $exportData
    }
    
    Write-Output ($result | ConvertTo-Json -Depth 10)  
}