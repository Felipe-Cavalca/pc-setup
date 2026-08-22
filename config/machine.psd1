@{
    SchemaVersion = '1.0'
    ProfileName   = 'felipe-adaptive'

    Execution = @{
        # Unattended não faz perguntas durante -Apply. Valores ausentes ou ambíguos interrompem com erro.
        Mode                      = 'Unattended'
        OnMissingSetting          = 'Stop'
        CollectSecretsBeforeApply = $true
        StoreSecretsInRepository  = $false
    }

    Windows = @{
        Edition      = 'Professional'
        TargetVersion = '25H2'
        MinimumBuild  = 26200
    }

    Machine = @{
        # Vazio preserva o nome escolhido durante a instalação do Windows.
        ComputerName = ''
        PrimaryUser  = 'Felipe'
    }

    Storage = @{
        System = @{
            # Localiza o volume do Windows em tempo de execução; não pressupõe C: nem um modelo de disco.
            Selection      = 'CurrentWindowsVolume'
            RequireHealthy = $true
        }

        Data = @{
            # UseIfAvailable responde "sim" ao uso de um único segundo disco fixo.
            # Valores aceitos: UseIfAvailable, Ask ou Ignore.
            Mode                       = 'Adaptive'
            SecondaryDiskPolicy        = 'UseIfAvailable'
            OnMultipleCandidates       = 'Stop'
            SingleDiskFallbackRoot     = '{SystemRoot}\Dados'
            AllowRemovableVolumes      = $false
            RequireHealthy             = $true
        }

        # Caminhos relativos a Storage.Data.Root. {PrimaryUser} será substituído pelo usuário principal.
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
            Name    = 'Felipe'
            Role    = 'Standard'
        }
        RecoveryAdmin = @{
            Enabled = $true
            Name    = 'Admin'
            Role    = 'Administrator'
        }
        Codex = @{
            Enabled = $true
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
        HyperV                  = $true
        WindowsSandbox          = $true
        VirtualMachinePlatform  = $true
        WSL                     = $true
        PublicVirtualMachine    = $false
    }

    Packages = @{
        Enabled                  = $true
        PreferredSource          = 'winget'
        PreferCurrentVersion     = $true
        Profiles                 = @('base', 'development', 'gaming')
        AllowOfflineFallback     = $true
        OfflineInstallerDirectory = 'installers'
        OfflineManifest            = 'config\offline-installers.psd1'
        RetryCount                 = 2
    }

    WSL = @{
        Update         = $true
        DefaultVersion = 2
        Distribution   = ''
    }

    Personalization = @{
        # Será habilitado quando existir um arquivo de plano de fundo revisado no projeto.
        Enabled       = $false
        WallpaperPath = ''
    }

    Debloat = @{
        Enabled              = $false
        Mode                 = 'ReviewThenApply'
        Repository           = 'Raphire/Win11Debloat'
        Release              = '2026.07.11'
        ArchiveSha256        = ''
        RequireSha256        = $true
        RequireConfirmation  = $true
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
        StopOnError     = $true
        RequirePlanBeforeApply = $true
    }
}
