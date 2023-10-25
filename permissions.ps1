#####################################################
# HelloID-Conn-Prov-Target-AFAS-Profit-Users-Permissions
#
# Version: 2.1.0
#####################################################
$permissions = @(
    @{
        DisplayName    = "InSite"
        Identification = @{
            Id   = "InSi"
            Name = "InSite"
        }
    },
    @{
        DisplayName    = "OutSite"
        Identification = @{
            Id   = "Site"
            Name = "OutSite"
        }
    },
    @{
        DisplayName    = "Profit Windows"
        Identification = @{
            Id   = "Awin"
            Name = "Profit Windows"
        }
    },
    @{
        DisplayName    = "Connector"
        Identification = @{
            Id   = "Acon"
            Name = "Connector"
        }
    },
    @{
        DisplayName    = "Backups from the command line"
        Identification = @{
            Id   = "Abac"
            Name = "Backups from the command line"
        }
    },
    @{
        DisplayName    = "Command line"
        Identification = @{
            Id   = "Acom"
            Name = "Command line"
        }
    },
    @{
        DisplayName    = "Activate collaboration license"
        Identification = @{
            Id   = "OcUs"
            Name = "Activate collaboration license"
        }
    },
    @{
        DisplayName    = "AFAS Online Portal administrator"
        Identification = @{
            Id   = "PoMa"
            Name = "AFAS Online Portal administrator"
        }
    },
    @{
        DisplayName    = "AFAS Accept"
        Identification = @{
            Id   = "AcUs"
            Name = "AFAS Accept"
        }
    }
)
Write-Output $permissions | ConvertTo-Json -Depth 10