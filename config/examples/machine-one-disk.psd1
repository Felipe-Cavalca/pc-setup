@{
    SchemaVersion = '1.0'
    ProfileName   = 'generic-one-disk'

    Execution = @{
        Mode                      = 'Unattended'
        OnMissingSetting          = 'Stop'
        CollectSecretsBeforeApply = $true
        StoreSecretsInRepository  = $false
    }

    Windows = @{
        Edition       = 'Professional'
        TargetVersion = '25H2'
        MinimumBuild  = 26200
    }

    Machine = @{
        ComputerName = ''
        PrimaryUser  = 'Usuario'
    }

    Storage = @{
        System = @{
            Selection      = 'CurrentWindowsVolume'
            RequireHealthy = $true
        }

        Data = @{
            Mode                   = 'DirectoryOnSystemVolume'
            SecondaryDiskPolicy    = 'Ignore'
            OnMultipleCandidates   = 'Stop'
            Root                   = '{SystemRoot}\Dados'
            AllowRemovableVolumes  = $false
            RequireHealthy         = $true
        }

        Paths = @{
            Apps         = 'Apps'
            Games        = 'Games'
            Development  = 'Dev'
            PersonalData = 'Data\{PrimaryUser}'
            Shared       = 'Shared'
            Downloads    = 'Downloads'
            VirtualMachines = 'VMs'
            Containers   = 'Containers'
            AgentData    = 'Agent\Codex'
        }
    }

    Accounts = @{
        DailyUser = @{
            Enabled = $true
            Name    = 'Usuario'
            Role    = 'Standard'
        }
        RecoveryAdmin = @{
            Enabled = $true
            Name    = 'Admin'
            Role    = 'Administrator'
        }
        Codex = @{
            Enabled = $false
            Name    = 'Codex'
            Role    = 'Standard'
        }
        God = @{
            Enabled = $false
            Name    = 'God'
            Role    = 'Administrator'
        }
        Public = @{
            Enabled = $false
            Name    = 'Publico'
            Role    = 'Standard'
            VirtualMachineName = 'Publico'
        }
    }

    Features = @{
        HyperV                 = $false
        WindowsSandbox         = $false
        VirtualMachinePlatform = $false
        WSL                    = $false
        PublicVirtualMachine   = $false
    }

    Packages = @{
        Enabled                   = $true
        PreferredSource           = 'winget'
        PreferCurrentVersion      = $true
        Profiles                  = @('base')
        AllowOfflineFallback      = $true
        OfflineInstallerDirectory = 'installers'
        OfflineManifest            = 'config\offline-installers.psd1'
        RetryCount                 = 2
    }

    WSL = @{
        Update         = $true
        DefaultVersion = 2
        Distribution   = ''
        Environments   = @{
            DailyUser = @{
                Enabled      = $false
                AccountKey   = 'DailyUser'
                Distribution = 'Ubuntu-24.04'
                Profile      = 'wsl\profiles\generic-user.psd1'
            }
        }
    }

    Personalization = @{
        Enabled       = $false
        WallpaperPath = ''
    }

    Debloat = @{
        Enabled             = $false
        Mode                = 'ReviewThenApply'
        Repository          = 'Raphire/Win11Debloat'
        Release             = '2026.07.11'
        ArchiveSha256       = ''
        RequireSha256       = $true
        RequireConfirmation = $true
    }

    Recovery = @{
        RequireRestorePointBeforeChanges  = $true
        Scope                             = 'ApplySession'
        SystemProtectionMustBeEnabled     = $true
        EnableSystemProtectionAutomatically = $false
        FailIfRestorePointUnavailable     = $true
        AllowExistingRestorePointReuse    = $false
        AllowSameApplySessionReuse        = $true
        ProtectDirectScriptExecution      = $true
    }

    Security = @{
        DailyUserMustBeStandard = $true
        BackupAclBeforeChanges  = $true
        ManageBitLocker         = $false
        BitLockerMode           = 'DoNotConfigure'
        ReportBitLockerStatus   = $true
        RequireRecoveryKeyCheck = $false
        DemoteDailyUserAutomatically = $false
    }

    Runtime = @{
        StateDirectory  = '{ProgramData}\pc-setup'
        ReportDirectory = '{ProgramData}\pc-setup\reports'
        WingetInventoryPath = '{ProgramData}\pc-setup\winget-installed.json'
        StopOnError     = $true
        RequirePlanBeforeApply = $true
    }
}
