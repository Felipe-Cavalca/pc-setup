@{
    SchemaVersion = '1.0'
    ProfileName   = 'generic-one-disk'

    Execution = @{
        Mode                      = 'Unattended'
        OnMissingSetting          = 'Stop'
        CollectSecretsBeforeApply = $true
        StoreSecretsInRepository  = $false
    }

    Reconciliation = @{
        Mode                        = 'Additive'
        DisableUnrequestedFeatures = $false
        RemoveDisabledAccounts      = $false
        RemoveUnlistedPackages      = $false
        RemoveUnlistedDirectories   = $false
    }

    Windows = @{
        Edition       = 'Professional'
        TargetVersion = ''
        MinimumBuild  = 22000
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
            DedicatedVolumeSubdirectory = ''
            Root                   = '{SystemRoot}\Dados'
            AllowRemovableVolumes  = $false
            RequireHealthy         = $true
        }

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
            HyperV = @{ Enabled = $false; PathKey = 'VirtualMachines'; Mode = 'Automatic' }
            Docker = @{ Enabled = $false; PathKey = 'Containers'; Mode = 'ManualRequired' }
            Steam  = @{ Enabled = $false; PathKey = 'Games'; Mode = 'ManualRequired' }
            Epic   = @{ Enabled = $false; PathKey = 'Games'; Mode = 'ManualRequired' }
        }
    }

    Backup = @{
        Enabled              = $false
        StagingPathKey       = 'Backups'
        SourcePathKeys       = @('Development')
        UserProfileFolders   = @('Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos')
        IncludeSetupInventory = $true
        ExternalDestination  = ''
        VerifyHashes         = $true
        NoAutomaticDeletion  = $true
        RestoreTest = @{
            Enabled          = $false
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
            Name    = 'Usuario'
            Role    = 'Standard'
        }
        RecoveryAdmin = @{
            Enabled = $true
            Name    = 'Admin'
            Role    = 'Administrator'
        }
        Public = @{
            Enabled = $false
            Name    = 'Publico'
            Role    = 'Standard'
            VirtualMachineName = 'Publico'
        }
    }

    Agent = @{
        Enabled        = $false
        Environment    = 'Agent'
        DefaultCommand = 'codex'
        Isolation      = 'AiJail'
        Harness = @{
            Enabled        = $false
            PackageManager = 'Npm'
            Package        = '@openai/codex'
            Version        = 'latest'
        }
        Memory = @{
            Enabled            = $false
            Repository         = 'akitaonrails/ai-memory'
            Version            = 'latest'
            Architecture       = 'x86_64'
            Sha256             = ''
            RequireAssetDigest = $true
            Client             = 'codex'
            ProjectStrategy    = 'repo-root'
            ServerUrl          = 'http://127.0.0.1:49374'
            LaunchMode         = 'Direct'
        }

        Launcher = @{
            DefaultMode   = 'Direct'
            PromptForMode = $false
            ReviewEnabled = $false
        }
        Workspace = @{
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

        EnvironmentAllowList = @()
        VirtualMachine = @{
            Enabled = $false
            Name    = 'Agent'
        }

        RestrictedMode = @{
            Enabled  = $false
            Lockdown = $true
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
        InstallScope              = 'machine'
        DefaultCriticality        = 'optional'
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
                Default      = $true
            }
            Agent = @{
                Enabled      = $false
                AccountKey   = 'DailyUser'
                Distribution = 'Ubuntu-24.04'
                Profile      = 'wsl\profiles\agent.psd1'
                Default      = $false
            }
        }
    }

    Personalization = @{
        Enabled                  = $true
        ApplyOnInstall           = $true
        PromptOnUpdate           = $true
        Theme                    = 'Dark'
        HideTaskbarSearch        = $true
        HideTaskView             = $true
        DisableWebSearch         = $true
        WebSearchMode            = 'Supported'
        ClearStartPins           = $true
        StartAllAppsView         = 'Category'
        StartPowerMenuFolders    = @('Settings')
        Taskbar = @{
            Enabled            = $true
            ReplaceDefaultPins = $true
            PinGeneration      = 1
            Pins = @(
                @{ Type = 'DesktopApplicationID';       Value = 'Microsoft.Windows.Explorer' }
                @{ Type = 'DesktopApplicationID';       Value = 'Brave.5JYAMH4N45CID63PRQ7VEXIY74' }
                @{ Type = 'DesktopApplicationID';       Value = 'Microsoft.VisualStudioCode' }
                @{ Type = 'AppUserModelID';             Value = 'Microsoft.WindowsTerminal_8wekyb3d8bbwe!App' }
                @{ Type = 'DesktopApplicationLinkPath'; Value = '%APPDATA%\Microsoft\Windows\Start Menu\Programs\Proton Mail.lnk' }
                @{ Type = 'DesktopApplicationID';       Value = 'Microsoft.Windows.Containers.Sandbox' }
            )
        }
        DisableEdgeBackground    = $true
        RemoveOneDrive           = $true
        RemoveAppxPackages       = @('7EE7776C.LinkedInforWindows', 'Microsoft.OutlookForWindows', '*LinkedIn*')
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
            Enabled = $false
            Mode    = 'Streaming'
            PathKey = 'Drive'
        }
        WallpaperPath            = ''
        LockScreen = @{
            Enabled          = $false
            Mode             = 'Manual'
            ImagePath        = ''
            DisableSpotlight = $true
            ShowOnSignIn     = $true
            Status           = 'None'
        }
    }

    Versions = @{
        Mode                    = 'Latest'
        LockFile                = 'config\versions.lock.json'
        CaptureKnownGood        = $true
    }

    Debloat = @{
        Enabled             = $false
        Mode                = 'ReviewThenApply'
        Repository          = 'Raphire/Win11Debloat'
        Release             = '2026.07.11'
        ArchiveSha256       = ''
        Preset              = 'RunDefaults'
        Silent              = $true
        AppRemovalTarget    = 'AllUsers'
        RemoveGamingApps    = $false
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
        HyperVAdministratorAccounts = @()
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
