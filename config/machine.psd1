@{
    SchemaVersion = '1.0'
    ProfileName   = 'felipe-adaptive'

    Execution = @{
        # Interactive permite escolher o disco de dados no plano; a aplicacao reutiliza essa escolha.
        Mode                      = 'Interactive'
        OnMissingSetting          = 'Stop'
        CollectSecretsBeforeApply = $true
        StoreSecretsInRepository  = $false
    }

    Reconciliation = @{
        # O pc-setup converge de forma aditiva: nao remove estado que deixou de ser listado.
        Mode                       = 'Additive'
        DisableUnrequestedFeatures = $false
        RemoveDisabledAccounts     = $false
        RemoveUnlistedPackages     = $false
        RemoveUnlistedDirectories  = $false
    }

    Windows = @{
        Edition      = 'Professional'
        # Vazio aceita qualquer versao do Windows 11; a build minima ainda impede Windows 10.
        TargetVersion = ''
        MinimumBuild  = 22000
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
            # Ask pergunta se um segundo disco fixo deve ser usado quando houver um candidato seguro.
            # Valores aceitos: UseIfAvailable, Ask ou Ignore.
            Mode                       = 'Adaptive'
            SecondaryDiskPolicy        = 'Ask'
            OnMultipleCandidates       = 'Stop'
            # Vazio usa a raiz do segundo volume (por exemplo, D:\). Use 'Dados' para D:\Dados.
            DedicatedVolumeSubdirectory = ''
            SingleDiskFallbackRoot     = '{SystemRoot}\Dados'
            AllowRemovableVolumes      = $false
            RequireHealthy             = $true
        }

        # Caminhos relativos a Storage.Data.Root. {PrimaryUser} será substituído pelo usuário principal.
        Paths = @{
            UserRoot     = '{PrimaryUser}'
            Apps         = '{PrimaryUser}\Apps'
            Games        = '{PrimaryUser}\Games'
            Development  = '{PrimaryUser}\Dev'
            Drive        = '{PrimaryUser}\Drive'
            Shared       = 'Shared'
            VirtualMachines = '{PrimaryUser}\VMs'
            Containers   = '{PrimaryUser}\Containers'
            Backups      = 'Backups'
        }

        Integrations = @{
            HyperV = @{
                Enabled = $true
                PathKey = 'VirtualMachines'
                Mode    = 'Automatic'
            }
            Docker = @{
                Enabled = $true
                PathKey = 'Containers'
                Mode    = 'ManualRequired'
            }
            Steam = @{
                Enabled = $true
                PathKey = 'Games'
                Mode    = 'ManualRequired'
            }
            Epic = @{
                Enabled = $true
                PathKey = 'Games'
                Mode    = 'ManualRequired'
            }
        }
    }

    Backup = @{
        Enabled              = $true
        StagingPathKey       = 'Backups'
        SourcePathKeys       = @('Development')
        UserProfileFolders   = @('Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos')
        IncludeSetupInventory = $true
        ExternalDestination  = ''
        VerifyHashes         = $true
        NoAutomaticDeletion  = $true
        RestoreTest = @{
            Enabled          = $true
            Destination      = '{LocalAppData}\pc-setup\restore-tests'
            KeepRestoredCopy = $false
        }
    }

    MachineAudit = @{
        Enabled                     = $true
        GenerateAfterReconciliation = $true
        OutputDirectory             = '{Desktop}'
        FileBaseName                = 'RESUMO-DA-MAQUINA'
        Formats                     = @('Html', 'Markdown')
    }

    PlanSummary = @{
        Enabled         = $true
        OutputDirectory = '{Desktop}'
        FileBaseName    = 'PLANO-PC-SETUP'
        Formats         = @('Html', 'Markdown')
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
        Public = @{
            Enabled = $true
            Name    = 'Publico'
            Role    = 'Standard'
            VirtualMachineName = 'Publico'
        }
    }

    Agent = @{
        Enabled         = $true
        Environment     = 'Agent'
        DefaultCommand  = 'codex'
        Isolation       = 'AiJail'

        Harness = @{
            Enabled        = $true
            PackageManager = 'Npm'
            Package        = '@openai/codex'
            Version        = 'latest'
        }

        Memory = @{
            Enabled            = $true
            Repository         = 'akitaonrails/ai-memory'
            Version            = 'latest'
            Architecture       = 'x86_64'
            Sha256             = ''
            RequireAssetDigest = $true
            Client             = 'codex'
            ProjectStrategy    = 'repo-root'
            ServerUrl          = 'http://127.0.0.1:49374'
            LaunchMode         = 'Managed'
        }

        Launcher = @{
            # Um unico AGENTE.cmd apresenta os modos; Enter usa o fluxo normal gerenciado.
            DefaultMode  = 'Managed'
            PromptForMode = $true
            ReviewEnabled = $true
        }

        Workspace = @{
            # O launcher concede acesso apenas ao projeto escolhido em cada execucao.
            Mode        = 'SelectedProjectOnly'
            DefaultPath = ''
        }

        Capabilities = @{
            Network           = $true
            PersistAgentState = $true
            Docker            = $false
            SSH               = $false
            Display           = $false
            GPU               = $false
            X11               = $false
            HostSharedMemory  = $false
            TerminalPassthrough = $false
            InheritEnvironment = $false
            UpdateCheck       = $false
            Worktree          = $false
            SystemdUser       = $false
            Tailscale         = $false
            Pictures          = $false
        }

        # Regras relativas ao projeto, aplicadas pelo launcher em toda execucao.
        ProjectSecrets = @{
            DenyPaths = @(
                '.env'
                '.env.local'
                '.env.*.local'
                'credentials.json'
                'secrets/**'
            )
            DenyPathExceptions = @()
            PreflightMode      = 'Warn'
        }

        # Somente nomes. Valores permanecem no ambiente local e nunca entram no repositorio.
        EnvironmentAllowList = @()

        # Apenas reserva a decisao para uma configuracao futura; nenhuma VM e criada pelo setup.
        VirtualMachine = @{
            Enabled = $false
            Name    = 'Agent'
        }

        RestrictedMode = @{
            Enabled  = $true
            # O modo normal ja usa home privado e capacidades minimas. Lockdown deixa o projeto somente leitura
            # e remove rede/estado de autenticacao, portanto nao serve para o Codex interativo padrao.
            Lockdown = $false
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
        InstallScope             = 'machine'
        DefaultCriticality       = 'optional'
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
        Environments   = @{
            DailyUser = @{
                Enabled      = $true
                AccountKey   = 'DailyUser'
                Distribution = 'Ubuntu-24.04'
                Profile      = 'wsl\profiles\daily-user.psd1'
                Default      = $true
            }
            Agent = @{
                Enabled      = $true
                AccountKey   = 'DailyUser'
                Distribution = 'Ubuntu-24.04'
                Profile      = 'wsl\profiles\agent.psd1'
                Default      = $false
            }
        }
    }

    Personalization = @{
        # Configuracoes do perfil diario; cada opcao pode ser alterada sem guardar segredos.
        Enabled                  = $true
        ApplyOnInstall           = $true
        PromptOnUpdate           = $true
        Theme                    = 'Dark'
        HideTaskbarSearch        = $true
        HideTaskView             = $true
        DisableWebSearch         = $true
        ClearStartPins           = $true
        StartAllAppsView         = 'Category'
        StartPowerMenuFolders    = @('Settings')
        DisableEdgeBackground    = $true
        RemoveOneDrive           = $true
        RemoveAppxPackages       = @('*LinkedIn*')
        PreserveAppxPackages     = @('Microsoft.YourPhone', 'MicrosoftWindows.CrossDevice')
        RedirectKnownFolders     = $false
        RestoreKnownFoldersToProfile = $true
        KnownFoldersPathKey      = 'UserRoot'
        KnownFolders             = @('Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos')
        CopyKnownFolderContent   = $true
        ProfileLink = @{
            Enabled = $true
            PathKey = 'UserRoot'
            Name    = 'Data'
        }
        GoogleDrive = @{
            Enabled = $true
            Mode    = 'Streaming'
            PathKey = 'Drive'
        }
        # Coloque a imagem dentro do projeto e informe o caminho relativo; vazio mantem o plano atual.
        WallpaperPath            = 'config\wallpapers\gargantua-realistic.png'
    }

    Versions = @{
        Mode                    = 'Latest'
        LockFile                = 'config\versions.lock.json'
        CaptureKnownGood        = $true
    }

    Debloat = @{
        Enabled              = $true
        Mode                 = 'ReviewThenApply'
        Repository           = 'Raphire/Win11Debloat'
        Release              = '2026.07.11'
        ArchiveSha256        = 'e97c8e36698c7b543da0b77cc34439c1a0b4917525b45a9d1ae7a02e23d4711d'
        Preset               = 'RunDefaults'
        Silent               = $true
        AppRemovalTarget     = 'AllUsers'
        RemoveGamingApps     = $false
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
        UserPhaseReceiptMaxAgeHours       = 24
    }

    Security = @{
        DailyUserMustBeStandard = $true
        BackupAclBeforeChanges  = $true
        ManageBitLocker         = $false
        BitLockerMode           = 'DoNotConfigure'
        ReportBitLockerStatus   = $true
        RequireRecoveryKeyCheck = $false
        DemoteDailyUserAutomatically = $false
        HyperVAdministratorAccounts = @('DailyUser')
    }

    Runtime = @{
        StateDirectory  = '{ProgramData}\pc-setup'
        ReportDirectory = '{ProgramData}\pc-setup\reports'
        UserStateDirectory  = '{LocalAppData}\pc-setup'
        UserReportDirectory = '{LocalAppData}\pc-setup\reports'
        WingetInventoryPath = '{LocalAppData}\pc-setup\winget-installed.json'
        KnownGoodVersionPath = '{LocalAppData}\pc-setup\versions-known-good.json'
        ExecutionLogEnabled = $true
        StopOnError     = $true
        RequirePlanBeforeApply = $true
    }
}
