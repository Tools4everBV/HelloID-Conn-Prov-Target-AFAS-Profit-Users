############################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Permissions
# PowerShell V2
############################################################

try {
    $retrievedPermissions = @(
        # @{ DisplayName = 'InSite Access'; Reference = 'InSi' }
        @{ DisplayName = 'Profit Windows access'; Reference = 'Awin' }
        @{ DisplayName = 'Activate collaboration license'; Reference = 'OcUs' },
        @{ DisplayName = 'AFAS Online Portal administrator'; Reference = 'PoMa' },
        @{ DisplayName = 'AFAS Accept'; Reference = 'AcUs' }
    )

    foreach ($permission in $retrievedPermissions) {
        $outputContext.Permissions.Add(@{
                DisplayName    = $permission.DisplayName
                Identification = @{
                    Reference = $permission.Reference
                }
            })
    }
}
catch {
    $ex = $PSItem
    Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
}
