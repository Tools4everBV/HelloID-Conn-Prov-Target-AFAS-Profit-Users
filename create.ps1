#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Create
#
# Version: 3.0.0 | new-powershell-connector
#####################################################

# Set to false at start, at the end, only when no error occurs it is set to true
$outputContext.Success = $false 

# AccountReference must have a value for dryRun
$outputContext.AccountReference = "Unknown"

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
    $account = $actionContext.Data
    $exportData = $account.PsObject.Copy()

    # Remove field because only used for export data or to set correlation
    if ($account.PSObject.Properties.Name -Contains 'Gebruiker') {
        $account.PSObject.Properties.Remove('Gebruiker')
    }
    if ($account.PSObject.Properties.Name -Contains 'Medewerker') {
        $account.PSObject.Properties.Remove('Medewerker')
    }

    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationProperty = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue
    
        if ([string]::IsNullOrEmpty($correlationProperty)) {
            Write-Warning "Correlation is enabled but not configured correctly."
            throw "Correlation is enabled but not configured correctly."
        }
    
        if ([string]::IsNullOrEmpty($correlationValue)) {
            Write-Warning "The correlation value for [$correlationProperty] is empty. This is likely a scripting issue."
            throw "The correlation value for [$correlationProperty] is empty. This is likely a scripting issue."
        }
    }
    else {
        Write-Warning "Correlation is enabled but not configured correctly."
        throw "Configuration of correlation is madatory."
    }

    # Get current account and verify if the action should be either [updated and correlated] or just [correlated]
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
            if ($($actionContext.Configuration.createUser) -eq $true) {
                Write-Verbose "No AFAS user found where [$($correlationProperty)] = [$($correlationValue)]. Creating new user"
            }
            else {
                throw "No AFAS user found where [$($correlationProperty)] = [$($correlationValue)] and [create user when not found in AFAS] set to [$($actionContext.Configuration.createUser)]"
            }
        }
        else {
            $aRef = [PSCustomObject]@{
                Gebruiker = $currentAccount.Gebruiker
            }

            $outputContext.AccountReference = $aRef

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CorrelateAccount"
                    Message = "Successfully correlated to AFAS user [$($currentAccount.Gebruiker)]"
                    IsError = $false
                })
            $outputContext.AccountCorrelated = $true    
        }
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount"
                Message = "Error querying AFAS user where [$($correlationProperty)] = [$($correlationValue)]. Error Message: $($errorMessage.AuditErrorMessage)"
                IsError = $true
            })
        
        # Skip further actions, as this is a critical error
        throw "Error querying AFAS user"
    }

    # Only create
    if (!$outputContext.AccountCorrelated) { 
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
                Uri             = "$($actionContext.Configuration.BaseUri)/connectors/$($actionContext.Configuration.UpdateConnector)"
                Headers         = $headers
                Method          = 'PUT'
                Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                ContentType     = "application/json;charset=utf-8"
                UseBasicParsing = $true
            }

            if (-Not($actionContext.DryRun -eq $true)) {
                Write-Verbose "Creating AFAS user [$($account.UsId)]. Account object: $($createAccount | ConvertTo-Json -Depth 10)" 

                $createdAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false

                # Set aRef object for use in futher actions
                $aRef = [PSCustomObject]@{
                    Gebruiker = $account.UsId
                }

                $outputContext.AccountReference = $aRef

                # Add correlation property to exportdata
                $exportData | Add-Member -MemberType NoteProperty -Name $correlationProperty -Value $correlationValue -Force
                # Add aRef properties to exportdata
                foreach ($aRefProperty in $aRef.PSObject.Properties) {
                    $exportData | Add-Member -MemberType NoteProperty -Name $aRefProperty.Name -Value $aRefProperty.Value -Force
                }

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = "CreateAccount"
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
                    
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CreateAccount"
                    Message = "Error creating AFAS user [$($account.UsId)]. Error Message: $($errorMessage.AuditErrorMessage). Account object: $($createAccount | ConvertTo-Json -Depth 10)"
                    IsError = $true
                })

            # Skip further actions, as this is a critical error
            throw "Error creating AFAS user"
        }
    }
}
catch {
    $ex = $PSItem
    if ((-Not($ex.Exception.Message -eq 'Error querying AFAS user')) -and (-Not($ex.Exception.Message -eq 'Error creating AFAS user'))) {
    
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount"
                Message = "$($ex.Exception.Message)"
                IsError = $true
            })
    } 
    else {
        Write-Verbose "ERROR: $ex"
    }
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($outputContext.AuditLogs.IsError -contains $true)) {
        $outputContext.Success = $true
    }

    $outputContext.Data = $exportData
}