Set-StrictMode -Version 2.0

function Get-PcSetupExecutionMode {
    [CmdletBinding()]
    param([switch]$Plan, [switch]$Apply)

    if ($Plan -and $Apply) { throw 'Use apenas -Plan ou -Apply.' }
    if ($Apply) { return 'Apply' }
    return 'Plan'
}

function Test-PcSetupAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-PcSetupAdministrator {
    if (-not (Test-PcSetupAdministrator)) {
        throw 'Execute a aplicacao em um PowerShell elevado (Administrador).'
    }
}

function Assert-PcSetupTableKey {
    param(
        [Parameter(Mandatory)][hashtable]$Table,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Path
    )

    if (-not $Table.ContainsKey($Key)) {
        throw "Configuracao obrigatoria ausente: $Path.$Key"
    }
}

function Import-PcSetupConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $configuration = Import-PowerShellDataFile -LiteralPath $resolvedPath
    if (-not ($configuration -is [hashtable])) { throw 'O arquivo de configuracao deve retornar uma hashtable.' }
    $configuration['_ConfigPath'] = $resolvedPath
    $configuration['_ProjectRoot'] = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    if ($configuration.Packages -is [hashtable] -and -not $configuration.Packages.ContainsKey('DefaultCriticality')) {
        $configuration.Packages['DefaultCriticality'] = 'optional'
    }
    if ($configuration.Runtime -is [hashtable] -and -not $configuration.Runtime.ContainsKey('KnownGoodVersionPath')) {
        $configuration.Runtime['KnownGoodVersionPath'] = '{LocalAppData}\pc-setup\versions-known-good.json'
    }
    if ($configuration.Runtime -is [hashtable] -and -not $configuration.Runtime.ContainsKey('ExecutionLogEnabled')) {
        $configuration.Runtime['ExecutionLogEnabled'] = $true
    }
    if ($configuration.Storage -is [hashtable] -and -not $configuration.Storage.ContainsKey('Integrations')) {
        $configuration.Storage['Integrations'] = @{
            HyperV = @{ Enabled = $false; PathKey = 'VirtualMachines'; Mode = 'Automatic' }
            Docker = @{ Enabled = $false; PathKey = 'Containers'; Mode = 'ManualRequired' }
            Steam  = @{ Enabled = $false; PathKey = 'Games'; Mode = 'ManualRequired' }
            Epic   = @{ Enabled = $false; PathKey = 'Games'; Mode = 'ManualRequired' }
        }
    }
    if (-not $configuration.ContainsKey('Backup')) {
        $configuration['Backup'] = @{
            Enabled = $false; StagingPathKey = 'Backups'; SourcePathKeys = @(); ExternalDestination = ''
            VerifyHashes = $true; NoAutomaticDeletion = $true
        }
    }
    if ($configuration.Backup -is [hashtable] -and -not $configuration.Backup.ContainsKey('RestoreTest')) {
        $configuration.Backup['RestoreTest'] = @{
            Enabled = $false; Destination = '{LocalAppData}\pc-setup\restore-tests'; KeepRestoredCopy = $false
        }
    }
    if (-not $configuration.ContainsKey('MachineAudit')) {
        $configuration['MachineAudit'] = @{
            Enabled = $false; GenerateAfterReconciliation = $false; OutputDirectory = '{Desktop}'
            FileBaseName = 'RESUMO-DA-MAQUINA'; Formats = @('Html', 'Markdown')
        }
    }
    if (-not $configuration.ContainsKey('PlanSummary')) {
        $configuration['PlanSummary'] = @{
            Enabled = $true; OutputDirectory = '{Desktop}'
            FileBaseName = 'PLANO-PC-SETUP'; Formats = @('Html', 'Markdown')
        }
    }
    if (-not $configuration.ContainsKey('Versions')) {
        $configuration['Versions'] = @{ Mode = 'Latest'; LockFile = 'config\versions.lock.json'; CaptureKnownGood = $true }
    }
    if ($configuration.Agent -is [hashtable] -and -not $configuration.Agent.ContainsKey('RestrictedMode')) {
        $configuration.Agent['RestrictedMode'] = @{ Enabled = $false; Lockdown = $true }
    }

    foreach ($key in @('SchemaVersion','ProfileName','Execution','Reconciliation','Windows','Machine','Storage','Backup','MachineAudit','PlanSummary','Accounts','Agent','Features','Packages','WSL','Personalization','Versions','Debloat','Recovery','Security','Runtime')) {
        Assert-PcSetupTableKey -Table $configuration -Key $key -Path 'config'
    }
    if ($configuration.Agent -is [hashtable] -and -not $configuration.Agent.ContainsKey('Memory')) {
        $configuration.Agent['Memory'] = @{
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
    }
    if ($configuration.Agent.Memory -is [hashtable] -and -not $configuration.Agent.Memory.ContainsKey('LaunchMode')) {
        $configuration.Agent.Memory['LaunchMode'] = 'Direct'
    }
    if ($configuration.Agent -is [hashtable] -and -not $configuration.Agent.ContainsKey('Launcher')) {
        $configuration.Agent['Launcher'] = @{ DefaultMode = 'Direct'; PromptForMode = $false; ReviewEnabled = $false }
    }
    if ($configuration.Agent -is [hashtable] -and -not $configuration.Agent.ContainsKey('EnvironmentAllowList')) {
        $configuration.Agent['EnvironmentAllowList'] = @()
    }
    $requiredKeys = @{
        Execution      = @('Mode','OnMissingSetting','CollectSecretsBeforeApply','StoreSecretsInRepository')
        Reconciliation = @('Mode','DisableUnrequestedFeatures','RemoveDisabledAccounts','RemoveUnlistedPackages','RemoveUnlistedDirectories')
        Windows        = @('Edition','TargetVersion','MinimumBuild')
        Machine        = @('ComputerName','PrimaryUser')
        Features       = @('HyperV','WindowsSandbox','VirtualMachinePlatform','WSL','PublicVirtualMachine')
        Packages       = @('Enabled','PreferredSource','PreferCurrentVersion','InstallScope','DefaultCriticality','Profiles','AllowOfflineFallback','OfflineInstallerDirectory','OfflineManifest','RetryCount')
        WSL            = @('Update','DefaultVersion','Distribution','Environments')
        Personalization = @('Enabled','WallpaperPath')
        Debloat        = @('Enabled','Mode','Repository','Release','ArchiveSha256','Preset','Silent','AppRemovalTarget','RemoveGamingApps','RequireSha256','RequireConfirmation')
        Recovery       = @('RequireRestorePointBeforeChanges','Scope','SystemProtectionMustBeEnabled','EnableSystemProtectionAutomatically','FailIfRestorePointUnavailable','AllowExistingRestorePointReuse','AllowSameApplySessionReuse','ProtectDirectScriptExecution','UserPhaseReceiptMaxAgeHours')
        Security       = @('DailyUserMustBeStandard','BackupAclBeforeChanges','ManageBitLocker','BitLockerMode','ReportBitLockerStatus','RequireRecoveryKeyCheck','DemoteDailyUserAutomatically','HyperVAdministratorAccounts')
        Runtime        = @('StateDirectory','ReportDirectory','UserStateDirectory','UserReportDirectory','WingetInventoryPath','KnownGoodVersionPath','ExecutionLogEnabled','StopOnError','RequirePlanBeforeApply')
        Agent          = @('Enabled','Environment','DefaultCommand','Isolation','Harness','Memory','Launcher','Workspace','Capabilities','EnvironmentAllowList','VirtualMachine','RestrictedMode')
        Backup         = @('Enabled','StagingPathKey','SourcePathKeys','ExternalDestination','VerifyHashes','NoAutomaticDeletion','RestoreTest')
        MachineAudit   = @('Enabled','GenerateAfterReconciliation','OutputDirectory','FileBaseName','Formats')
        PlanSummary    = @('Enabled','OutputDirectory','FileBaseName','Formats')
        Versions       = @('Mode','LockFile','CaptureKnownGood')
    }
    foreach ($section in $requiredKeys.Keys) {
        foreach ($key in $requiredKeys[$section]) { Assert-PcSetupTableKey -Table $configuration[$section] -Key $key -Path "config.$section" }
    }
    foreach ($key in @('System','Data','Paths','Integrations')) { Assert-PcSetupTableKey -Table $configuration.Storage -Key $key -Path 'config.Storage' }
    foreach ($key in @('Selection','RequireHealthy')) { Assert-PcSetupTableKey -Table $configuration.Storage.System -Key $key -Path 'config.Storage.System' }
    foreach ($key in @('Mode','SecondaryDiskPolicy','OnMultipleCandidates','AllowRemovableVolumes','RequireHealthy')) { Assert-PcSetupTableKey -Table $configuration.Storage.Data -Key $key -Path 'config.Storage.Data' }

    if ($configuration.SchemaVersion -ne '1.0') { throw "SchemaVersion nao suportada: $($configuration.SchemaVersion)" }
    if ($configuration.Execution.Mode -notin @('Unattended','Interactive')) { throw 'Execution.Mode deve ser Unattended ou Interactive.' }
    if ($configuration.Execution.OnMissingSetting -ne 'Stop' -or -not $configuration.Execution.CollectSecretsBeforeApply) { throw 'Configuracoes ausentes devem interromper e segredos devem ser coletados antes das alteracoes dependentes.' }
    if ($configuration.Execution.StoreSecretsInRepository -ne $false) { throw 'StoreSecretsInRepository deve permanecer false.' }
    if ($configuration.Reconciliation.Mode -ne 'Additive') { throw 'Reconciliation.Mode suportado: Additive.' }
    foreach ($setting in @('DisableUnrequestedFeatures','RemoveDisabledAccounts','RemoveUnlistedPackages','RemoveUnlistedDirectories')) {
        if ($configuration.Reconciliation[$setting] -ne $false) { throw "Reconciliation.$setting ainda nao e suportado; mantenha false." }
    }
    if ($configuration.Storage.System.Selection -ne 'CurrentWindowsVolume') { throw 'Storage.System.Selection deve ser CurrentWindowsVolume.' }
    if ($configuration.Storage.Data.Mode -notin @('Adaptive','DirectoryOnSystemVolume')) { throw 'Storage.Data.Mode invalido.' }
    if ($configuration.Storage.Data.SecondaryDiskPolicy -notin @('UseIfAvailable','Ask','Ignore')) { throw 'SecondaryDiskPolicy invalida.' }
    if ($configuration.Storage.Data.OnMultipleCandidates -ne 'Stop') { throw 'Storage.Data.OnMultipleCandidates deve ser Stop.' }
    if ($configuration.Execution.Mode -eq 'Unattended' -and $configuration.Storage.Data.SecondaryDiskPolicy -eq 'Ask') {
        throw 'SecondaryDiskPolicy Ask nao pode ser usada com Execution.Mode Unattended.'
    }
    if ($configuration.Storage.Data.Mode -eq 'Adaptive' -and -not $configuration.Storage.Data.ContainsKey('SingleDiskFallbackRoot')) { throw 'Storage.Data.SingleDiskFallbackRoot e obrigatorio no modo Adaptive.' }
    if ($configuration.Storage.Data.Mode -eq 'DirectoryOnSystemVolume' -and -not $configuration.Storage.Data.ContainsKey('Root')) { throw 'Storage.Data.Root e obrigatorio no modo DirectoryOnSystemVolume.' }
    if ($configuration.Recovery.RequireRestorePointBeforeChanges -ne $true -or $configuration.Recovery.FailIfRestorePointUnavailable -ne $true) {
        throw 'O ponto de restauracao obrigatorio nao pode ser desabilitado.'
    }
    if (-not $configuration.Recovery.SystemProtectionMustBeEnabled) { throw 'SystemProtectionMustBeEnabled deve permanecer true.' }
    if ($configuration.Recovery.EnableSystemProtectionAutomatically -ne $false) {
        throw 'EnableSystemProtectionAutomatically deve permanecer false.'
    }
    if ($configuration.Recovery.Scope -ne 'ApplySession' -or -not $configuration.Recovery.ProtectDirectScriptExecution) { throw 'A recuperacao deve proteger a sessao Apply e execucoes diretas.' }
    if ($configuration.Security.ManageBitLocker -ne $false -or $configuration.Security.BitLockerMode -ne 'DoNotConfigure') {
        throw 'O perfil padrao nao pode gerenciar BitLocker.'
    }
    if (-not $configuration.Security.DailyUserMustBeStandard -or $configuration.Security.RequireRecoveryKeyCheck) {
        throw 'O usuario diario deve ser padrao e o setup nao pode exigir chave de recuperacao do BitLocker.'
    }
    if ($configuration.Security.BackupAclBeforeChanges -ne $true) { throw 'BackupAclBeforeChanges deve permanecer true.' }
    if ($configuration.Recovery.AllowExistingRestorePointReuse -ne $false) { throw 'Pontos de outras execucoes nao podem ser reutilizados.' }
    if ($configuration.Recovery.AllowSameApplySessionReuse -ne $true) { throw 'AllowSameApplySessionReuse deve permanecer true para retomadas seguras apos reinicio.' }
    if ([int]$configuration.Recovery.UserPhaseReceiptMaxAgeHours -lt 1 -or [int]$configuration.Recovery.UserPhaseReceiptMaxAgeHours -gt 24) { throw 'Recovery.UserPhaseReceiptMaxAgeHours deve ficar entre 1 e 24.' }
    if ($configuration.WSL.DefaultVersion -notin @(1, 2)) { throw 'WSL.DefaultVersion deve ser 1 ou 2.' }
    if ($configuration.WSL.ContainsKey('Environments')) {
        if (-not ($configuration.WSL.Environments -is [hashtable])) { throw 'WSL.Environments deve ser uma hashtable.' }
        foreach ($environmentName in @($configuration.WSL.Environments.Keys)) {
            if ([string]$environmentName -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "Nome de ambiente WSL invalido: $environmentName" }
            $environment = $configuration.WSL.Environments[$environmentName]
            if (-not ($environment -is [hashtable])) { throw "WSL.Environments.$environmentName deve ser uma hashtable." }
            foreach ($key in @('Enabled','AccountKey','Distribution','Profile','Default')) {
                Assert-PcSetupTableKey -Table $environment -Key $key -Path "config.WSL.Environments.$environmentName"
            }
            if ($environment.AccountKey -notin @('DailyUser','RecoveryAdmin','Public')) { throw "AccountKey invalido no ambiente WSL ${environmentName}: $($environment.AccountKey)" }
            if ([string]$environment.Distribution -notmatch '^[A-Za-z0-9._-]+$') { throw "Distribution invalida no ambiente WSL ${environmentName}: $($environment.Distribution)" }
            if ([IO.Path]::IsPathRooted([string]$environment.Profile) -or [string]$environment.Profile -match '(^|[\\/])\.\.([\\/]|$)') { throw "Profile invalido no ambiente WSL ${environmentName}." }
            if ($environment.Enabled -and -not $configuration.Features.WSL) { throw "O ambiente WSL $environmentName esta habilitado, mas Features.WSL esta desabilitado." }
            if ($environment.Enabled -and -not $configuration.Accounts[[string]$environment.AccountKey].Enabled) { throw "O ambiente WSL $environmentName usa uma conta Windows desabilitada." }
        }
    }
    if ($configuration.Packages.PreferredSource -ne 'winget' -or -not $configuration.Packages.PreferCurrentVersion) { throw 'Pacotes devem usar Winget e preferir a versao atual.' }
    if ($configuration.Packages.InstallScope -notin @('machine','user')) { throw 'Packages.InstallScope deve ser machine ou user.' }
    if ($configuration.Packages.DefaultCriticality -notin @('required','optional')) { throw 'Packages.DefaultCriticality deve ser required ou optional.' }
    if ([int]$configuration.Packages.RetryCount -lt 0 -or [int]$configuration.Packages.RetryCount -gt 5) { throw 'Packages.RetryCount deve ficar entre 0 e 5.' }
    if ([string]::IsNullOrWhiteSpace([string]$configuration.Packages.OfflineManifest)) { throw 'Packages.OfflineManifest nao pode ficar vazio.' }
    if (-not $configuration.Runtime.StopOnError -or -not $configuration.Runtime.RequirePlanBeforeApply) { throw 'Runtime deve interromper em erro e exigir plano antes da aplicacao.' }
    if (-not ($configuration.Runtime.ExecutionLogEnabled -is [bool])) { throw 'Runtime.ExecutionLogEnabled deve ser booleano.' }
    foreach ($integrationName in @('HyperV','Docker','Steam','Epic')) {
        Assert-PcSetupTableKey -Table $configuration.Storage.Integrations -Key $integrationName -Path 'config.Storage.Integrations'
        $integration = $configuration.Storage.Integrations[$integrationName]
        if (-not ($integration -is [hashtable])) { throw "Storage.Integrations.$integrationName deve ser uma hashtable." }
        foreach ($key in @('Enabled','PathKey','Mode')) { Assert-PcSetupTableKey -Table $integration -Key $key -Path "config.Storage.Integrations.$integrationName" }
        if ($integration.Enabled -and -not $configuration.Storage.Paths.ContainsKey([string]$integration.PathKey)) { throw "Storage.Integrations.$integrationName.PathKey nao existe em Storage.Paths." }
        $allowedModes = if ($integrationName -eq 'HyperV') { @('Automatic','ManualRequired') } else { @('ManualRequired') }
        if ([string]$integration.Mode -notin $allowedModes) { throw "Storage.Integrations.$integrationName.Mode invalido." }
    }
    if ($configuration.Storage.Integrations.HyperV.Enabled -and -not $configuration.Features.HyperV) { throw 'A integracao de armazenamento do Hyper-V exige Features.HyperV.' }
    if ($configuration.Backup.Enabled -and ([string]$configuration.Backup.StagingPathKey -eq '' -or -not $configuration.Storage.Paths.ContainsKey([string]$configuration.Backup.StagingPathKey))) {
        throw 'Backup.StagingPathKey deve apontar para uma entrada de Storage.Paths.'
    }
    $backupSources = @()
    foreach ($sourceKey in @($configuration.Backup.SourcePathKeys)) {
        $key = [string]$sourceKey
        if ($configuration.Backup.Enabled -and -not $configuration.Storage.Paths.ContainsKey($key)) { throw "Backup.SourcePathKeys referencia uma entrada inexistente: $key" }
        if ($key -eq [string]$configuration.Backup.StagingPathKey) { throw 'A pasta de staging nao pode ser uma origem do proprio backup.' }
        if ($backupSources -contains $key) { throw "Backup.SourcePathKeys contem item duplicado: $key" }
        $backupSources += $key
    }
    if ($configuration.Backup.Enabled -and $backupSources.Count -eq 0) { throw 'Backup habilitado exige ao menos uma origem.' }
    if ($configuration.Backup.Enabled -and $configuration.Backup.VerifyHashes -ne $true) { throw 'O backup habilitado deve verificar hashes.' }
    if ($configuration.Backup.NoAutomaticDeletion -ne $true) { throw 'Backup.NoAutomaticDeletion deve permanecer true.' }
    if ([string]$configuration.Backup.ExternalDestination -match "[`r`n]") { throw 'Backup.ExternalDestination nao pode conter quebra de linha.' }
    if (-not ($configuration.Backup.RestoreTest -is [hashtable])) { throw 'Backup.RestoreTest deve ser uma hashtable.' }
    foreach ($key in @('Enabled','Destination','KeepRestoredCopy')) { Assert-PcSetupTableKey -Table $configuration.Backup.RestoreTest -Key $key -Path 'config.Backup.RestoreTest' }
    if ($configuration.Backup.RestoreTest.Enabled -and [string]::IsNullOrWhiteSpace([string]$configuration.Backup.RestoreTest.Destination)) { throw 'Backup.RestoreTest.Destination nao pode ficar vazio.' }
    if ([string]$configuration.Backup.RestoreTest.Destination -match "[`r`n]") { throw 'Backup.RestoreTest.Destination nao pode conter quebra de linha.' }
    if (-not ($configuration.Backup.RestoreTest.KeepRestoredCopy -is [bool])) { throw 'Backup.RestoreTest.KeepRestoredCopy deve ser booleano.' }
    foreach ($key in @('Enabled','GenerateAfterReconciliation')) {
        if (-not ($configuration.MachineAudit[$key] -is [bool])) { throw "MachineAudit.$key deve ser booleano." }
    }
    if ($configuration.MachineAudit.GenerateAfterReconciliation -and -not $configuration.MachineAudit.Enabled) { throw 'MachineAudit.GenerateAfterReconciliation exige MachineAudit.Enabled.' }
    if ([string]::IsNullOrWhiteSpace([string]$configuration.MachineAudit.OutputDirectory) -or [string]$configuration.MachineAudit.OutputDirectory -match "[`r`n]") { throw 'MachineAudit.OutputDirectory invalido.' }
    if ([string]$configuration.MachineAudit.FileBaseName -notmatch '^[A-Za-z0-9._-]+$') { throw 'MachineAudit.FileBaseName deve usar apenas letras, numeros, ponto, hifen ou sublinhado.' }
    $auditFormats = @($configuration.MachineAudit.Formats | ForEach-Object { [string]$_ })
    if ($auditFormats.Count -eq 0 -or @($auditFormats | Where-Object { $_ -notin @('Html','Markdown') }).Count -gt 0) { throw 'MachineAudit.Formats aceita apenas Html e Markdown.' }
    $configuration.MachineAudit.Formats = @($auditFormats | Select-Object -Unique)
    if (-not ($configuration.PlanSummary.Enabled -is [bool])) { throw 'PlanSummary.Enabled deve ser booleano.' }
    if ([string]::IsNullOrWhiteSpace([string]$configuration.PlanSummary.OutputDirectory) -or [string]$configuration.PlanSummary.OutputDirectory -match "[`r`n]") { throw 'PlanSummary.OutputDirectory invalido.' }
    if ([string]$configuration.PlanSummary.FileBaseName -notmatch '^[A-Za-z0-9._-]+$') { throw 'PlanSummary.FileBaseName deve usar apenas letras, numeros, ponto, hifen ou sublinhado.' }
    $planFormats = @($configuration.PlanSummary.Formats | ForEach-Object { [string]$_ })
    if ($planFormats.Count -eq 0 -or @($planFormats | Where-Object { $_ -notin @('Html','Markdown') }).Count -gt 0) { throw 'PlanSummary.Formats aceita apenas Html e Markdown.' }
    $configuration.PlanSummary.Formats = @($planFormats | Select-Object -Unique)
    if ([string]$configuration.Versions.Mode -notin @('Latest','Locked')) { throw 'Versions.Mode deve ser Latest ou Locked.' }
    if ([string]::IsNullOrWhiteSpace([string]$configuration.Versions.LockFile)) { throw 'Versions.LockFile nao pode ficar vazio.' }
    $null = Resolve-PcSetupProjectPath -Configuration $configuration -Value ([string]$configuration.Versions.LockFile) -SettingName 'Versions.LockFile'
    if (-not ($configuration.Agent.RestrictedMode.Enabled -is [bool]) -or -not ($configuration.Agent.RestrictedMode.Lockdown -is [bool])) { throw 'Agent.RestrictedMode deve usar valores booleanos.' }
    if ($configuration.Agent.RestrictedMode.Enabled) {
        foreach ($capability in @('Docker','SSH','Display','GPU','X11','HostSharedMemory','TerminalPassthrough','InheritEnvironment','Worktree','SystemdUser','Tailscale','Pictures')) {
            if ($configuration.Agent.Capabilities[$capability]) { throw "O modo restrito exige Agent.Capabilities.$capability desabilitada." }
        }
    }
    if ($configuration.Debloat.Mode -ne 'ReviewThenApply' -or -not $configuration.Debloat.RequireConfirmation) { throw 'Debloat deve permanecer em modo ReviewThenApply com confirmacao.' }
    if ($configuration.Debloat.Preset -ne 'RunDefaults') { throw 'Debloat.Preset deve ser RunDefaults.' }
    if (-not ($configuration.Debloat.Silent -is [bool]) -or $configuration.Debloat.Silent -ne $true) { throw 'Debloat.Silent deve ser true para a execucao reproduzivel.' }
    if ($configuration.Debloat.AppRemovalTarget -ne 'AllUsers') { throw 'Debloat.AppRemovalTarget deve ser AllUsers.' }
    if (-not ($configuration.Debloat.RemoveGamingApps -is [bool])) { throw 'Debloat.RemoveGamingApps deve ser booleano.' }
    if ([string]::IsNullOrWhiteSpace([string]$configuration.Machine.PrimaryUser)) { throw 'Machine.PrimaryUser nao pode ficar vazio.' }
    if ([int]$configuration.Windows.MinimumBuild -lt 22000) { throw 'Windows.MinimumBuild deve exigir ao menos uma build do Windows 11.' }
    if (-not [string]::IsNullOrWhiteSpace([string]$configuration.Machine.ComputerName) -and [string]$configuration.Machine.ComputerName -notmatch '^(?!-)[A-Za-z0-9-]{1,15}(?<!-)$') {
        throw 'Machine.ComputerName deve ter ate 15 caracteres, usando letras, numeros ou hifen sem hifen nas extremidades.'
    }
    if (-not $configuration.Accounts.DailyUser.Enabled -or -not $configuration.Accounts.RecoveryAdmin.Enabled) {
        throw 'DailyUser e RecoveryAdmin devem permanecer habilitados.'
    }
    if ([string]$configuration.Machine.PrimaryUser -ne [string]$configuration.Accounts.DailyUser.Name) {
        throw 'Machine.PrimaryUser deve ser igual a Accounts.DailyUser.Name.'
    }

    foreach ($legacyAccount in @('Codex','God')) {
        if ($configuration.Accounts.ContainsKey($legacyAccount)) { throw "Accounts.$legacyAccount foi removida. Agentes devem usar o usuario Linux configurado em Agent." }
    }

    $accountNames = @()
    foreach ($accountKey in @('DailyUser','RecoveryAdmin','Public')) {
        Assert-PcSetupTableKey -Table $configuration.Accounts -Key $accountKey -Path 'config.Accounts'
        $account = $configuration.Accounts[$accountKey]
        if ($account.Enabled) {
            if ([string]::IsNullOrWhiteSpace([string]$account.Name)) { throw "Accounts.$accountKey.Name nao pode ficar vazio." }
            if ($account.Name -notmatch '^[^\\/:*?"<>|]{1,20}$') { throw "Nome de conta local invalido: $($account.Name)" }
            $normalizedName = $account.Name.ToLowerInvariant()
            if ($accountNames -contains $normalizedName) { throw "Conta duplicada na configuracao: $($account.Name)" }
            $accountNames += $normalizedName
            if ($account.Role -notin @('Standard','Administrator')) { throw "Accounts.$accountKey.Role invalido." }
        }
    }

    if (-not ($configuration.Agent.Capabilities -is [hashtable])) { throw 'Agent.Capabilities deve ser uma hashtable.' }
    foreach ($key in @('Network','PersistAgentState','Docker','SSH','Display','GPU','X11','HostSharedMemory','TerminalPassthrough','InheritEnvironment','UpdateCheck','Worktree','SystemdUser','Tailscale','Pictures')) {
        Assert-PcSetupTableKey -Table $configuration.Agent.Capabilities -Key $key -Path 'config.Agent.Capabilities'
    }
    if (-not $configuration.Agent.ContainsKey('ProjectSecrets')) {
        $configuration.Agent['ProjectSecrets'] = @{
            DenyPaths = @('.env', '.env.local', '.env.*.local', 'credentials.json', 'secrets/**')
            DenyPathExceptions = @()
            PreflightMode = 'Warn'
        }
    }
    if ($configuration.Agent.ProjectSecrets -is [hashtable] -and -not $configuration.Agent.ProjectSecrets.ContainsKey('PreflightMode')) {
        $configuration.Agent.ProjectSecrets['PreflightMode'] = 'Warn'
    }
    if (-not ($configuration.Agent.ProjectSecrets -is [hashtable])) { throw 'Agent.ProjectSecrets deve ser uma hashtable.' }
    foreach ($key in @('DenyPaths','DenyPathExceptions')) {
        Assert-PcSetupTableKey -Table $configuration.Agent.ProjectSecrets -Key $key -Path 'config.Agent.ProjectSecrets'
        $seenSecretPaths = @()
        foreach ($configuredPath in @($configuration.Agent.ProjectSecrets[$key])) {
            $secretPath = [string]$configuredPath
            if ([string]::IsNullOrWhiteSpace($secretPath) -or $secretPath -match "[`r`n\\]" -or $secretPath.StartsWith('/') -or $secretPath -match '^[A-Za-z]:' -or $secretPath -match '(^|/)\.\.?(/|$)') {
                throw "Agent.ProjectSecrets.$key contem um caminho inseguro: $secretPath"
            }
            if ($seenSecretPaths -contains $secretPath) { throw "Agent.ProjectSecrets.$key contem um caminho duplicado: $secretPath" }
            $seenSecretPaths += $secretPath
        }
    }
    if ([string]$configuration.Agent.ProjectSecrets.PreflightMode -notin @('Off','Warn','Stop')) { throw 'Agent.ProjectSecrets.PreflightMode deve ser Off, Warn ou Stop.' }
    if (-not ($configuration.Agent.Harness -is [hashtable])) { throw 'Agent.Harness deve ser uma hashtable.' }
    foreach ($key in @('Enabled','PackageManager','Package','Version')) { Assert-PcSetupTableKey -Table $configuration.Agent.Harness -Key $key -Path 'config.Agent.Harness' }
    if ($configuration.Agent.Harness.PackageManager -ne 'Npm') { throw 'Agent.Harness.PackageManager deve ser Npm.' }
    if ([string]$configuration.Agent.Harness.Package -notmatch '^@[a-z0-9._-]+/[a-z0-9._-]+$') { throw 'Agent.Harness.Package deve ser um pacote NPM com escopo.' }
    if ([string]$configuration.Agent.Harness.Version -ne 'latest' -and [string]$configuration.Agent.Harness.Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') { throw 'Agent.Harness.Version deve ser latest ou uma versao exata.' }
    if ($configuration.Agent.Enabled -and -not $configuration.Agent.Harness.Enabled) { throw 'O perfil padrao do agente exige Agent.Harness.Enabled.' }
    if (-not ($configuration.Agent.Memory -is [hashtable])) { throw 'Agent.Memory deve ser uma hashtable.' }
    foreach ($key in @('Enabled','Repository','Version','Architecture','Sha256','RequireAssetDigest','Client','ProjectStrategy','ServerUrl','LaunchMode')) { Assert-PcSetupTableKey -Table $configuration.Agent.Memory -Key $key -Path 'config.Agent.Memory' }
    if ($configuration.Agent.Memory.Enabled) {
        if (-not $configuration.Agent.Enabled) { throw 'Agent.Memory exige Agent.Enabled.' }
        if ([string]$configuration.Agent.Memory.Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Agent.Memory.Repository invalido.' }
        if ([string]$configuration.Agent.Memory.Version -ne 'latest' -and [string]$configuration.Agent.Memory.Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Agent.Memory.Version deve ser latest ou uma versao exata.' }
        if ([string]$configuration.Agent.Memory.Architecture -notmatch '^[a-z0-9_]+$') { throw 'Agent.Memory.Architecture invalida.' }
        if ([string]$configuration.Agent.Memory.Version -ne 'latest' -and [string]$configuration.Agent.Memory.Sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Agent.Memory com versao exata exige SHA-256.' }
        if ([string]$configuration.Agent.Memory.Version -eq 'latest' -and -not [string]::IsNullOrWhiteSpace([string]$configuration.Agent.Memory.Sha256)) { throw 'Agent.Memory.Sha256 deve ficar vazio com Version=latest.' }
        if ($configuration.Agent.Memory.RequireAssetDigest -ne $true) { throw 'Agent.Memory.RequireAssetDigest deve permanecer true.' }
        if ([string]$configuration.Agent.Memory.Client -notmatch '^[a-z0-9][a-z0-9-]*$') { throw 'Agent.Memory.Client invalido.' }
        if ([string]$configuration.Agent.Memory.ProjectStrategy -notin @('repo-root','basename')) { throw 'Agent.Memory.ProjectStrategy deve ser repo-root ou basename.' }
        if ([string]$configuration.Agent.Memory.LaunchMode -notin @('Direct','Managed')) { throw 'Agent.Memory.LaunchMode deve ser Direct ou Managed.' }
        $serverUrlMatch = [regex]::Match([string]$configuration.Agent.Memory.ServerUrl, '^http://127\.0\.0\.1:([1-9][0-9]{0,4})$')
        if (-not $serverUrlMatch.Success -or [int]$serverUrlMatch.Groups[1].Value -gt 65535) { throw 'Agent.Memory.ServerUrl deve usar loopback HTTP e uma porta valida.' }
    }
    if (-not ($configuration.Agent.Launcher -is [hashtable])) { throw 'Agent.Launcher deve ser uma hashtable.' }
    foreach ($key in @('DefaultMode','PromptForMode','ReviewEnabled')) { Assert-PcSetupTableKey -Table $configuration.Agent.Launcher -Key $key -Path 'config.Agent.Launcher' }
    if ([string]$configuration.Agent.Launcher.DefaultMode -notin @('Direct','Managed')) { throw 'Agent.Launcher.DefaultMode deve ser Direct ou Managed.' }
    if (-not ($configuration.Agent.Launcher.PromptForMode -is [bool]) -or -not ($configuration.Agent.Launcher.ReviewEnabled -is [bool])) { throw 'Agent.Launcher deve usar valores booleanos.' }
    if ([string]$configuration.Agent.Launcher.DefaultMode -eq 'Managed' -and (-not $configuration.Agent.Memory.Enabled -or [string]$configuration.Agent.Memory.LaunchMode -ne 'Managed')) { throw 'Agent.Launcher.DefaultMode Managed exige Agent.Memory habilitado com LaunchMode Managed.' }
    $environmentAllowList = @()
    foreach ($environmentVariable in @($configuration.Agent.EnvironmentAllowList)) {
        $name = [string]$environmentVariable
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { throw "Agent.EnvironmentAllowList contem nome invalido: $name" }
        if ($environmentAllowList -contains $name) { throw "Agent.EnvironmentAllowList contem item duplicado: $name" }
        $environmentAllowList += $name
    }
    $configuration.Agent.EnvironmentAllowList = $environmentAllowList
    if (-not ($configuration.Agent.Workspace -is [hashtable])) { throw 'Agent.Workspace deve ser uma hashtable.' }
    foreach ($key in @('Mode','DefaultPath')) { Assert-PcSetupTableKey -Table $configuration.Agent.Workspace -Key $key -Path 'config.Agent.Workspace' }
    if ($configuration.Agent.Workspace.Mode -ne 'SelectedProjectOnly') { throw 'Agent.Workspace.Mode deve ser SelectedProjectOnly.' }
    if ([string]$configuration.Agent.Workspace.DefaultPath -match "[`r`n]") { throw 'Agent.Workspace.DefaultPath nao pode conter quebra de linha.' }
    if (-not ($configuration.Agent.VirtualMachine -is [hashtable])) { throw 'Agent.VirtualMachine deve ser uma hashtable.' }
    foreach ($key in @('Enabled','Name')) { Assert-PcSetupTableKey -Table $configuration.Agent.VirtualMachine -Key $key -Path 'config.Agent.VirtualMachine' }
    if ($configuration.Agent.Isolation -ne 'AiJail') { throw 'Agent.Isolation deve ser AiJail.' }
    if ([string]$configuration.Agent.DefaultCommand -notmatch '^[A-Za-z0-9._-]+$') { throw 'Agent.DefaultCommand deve ser apenas o nome de um executavel.' }
    if ($configuration.Agent.Enabled -and -not $configuration.Features.WSL) { throw 'Agent habilitado exige Features.WSL.' }
    if ($configuration.Agent.VirtualMachine.Enabled -and -not $configuration.Features.HyperV) { throw 'A VM opcional do agente exige Features.HyperV.' }
    if ([string]::IsNullOrWhiteSpace([string]$configuration.Agent.VirtualMachine.Name)) { throw 'Agent.VirtualMachine.Name nao pode ficar vazio.' }
    if (-not $configuration.WSL.Environments.ContainsKey([string]$configuration.Agent.Environment)) { throw 'Agent.Environment deve apontar para um ambiente WSL declarado.' }
    $agentEnvironment = $configuration.WSL.Environments[[string]$configuration.Agent.Environment]
    if ([bool]$configuration.Agent.Enabled -ne [bool]$agentEnvironment.Enabled) { throw 'Agent.Enabled deve coincidir com o ambiente WSL do agente.' }
    if ($agentEnvironment.AccountKey -ne 'DailyUser') { throw 'O ambiente WSL do agente deve pertencer a Accounts.DailyUser.' }

    $hyperVAccountKeys = @()
    foreach ($accountKey in @($configuration.Security.HyperVAdministratorAccounts)) {
        $key = [string]$accountKey
        if ($key -notin @('DailyUser','RecoveryAdmin','Public')) { throw "Conta invalida em Security.HyperVAdministratorAccounts: $key" }
        if (-not $configuration.Accounts[$key].Enabled) { throw "Security.HyperVAdministratorAccounts referencia uma conta desabilitada: $key" }
        if ($hyperVAccountKeys -contains $key) { throw "Conta duplicada em Security.HyperVAdministratorAccounts: $key" }
        $hyperVAccountKeys += $key
    }
    if ($hyperVAccountKeys.Count -gt 0 -and -not $configuration.Features.HyperV) { throw 'HyperVAdministratorAccounts exige Features.HyperV.' }
    $configuration.Security.HyperVAdministratorAccounts = $hyperVAccountKeys

    foreach ($profile in @($configuration.Packages.Profiles)) {
        if ($profile -notmatch '^[a-z0-9-]+$') { throw "Nome de perfil de pacotes invalido: $profile" }
    }

    if ($configuration.Debloat.Enabled -and $configuration.Debloat.RequireSha256 -and ([string]$configuration.Debloat.ArchiveSha256 -notmatch '^[a-fA-F0-9]{64}$')) {
        throw 'Debloat habilitado exige ArchiveSha256 valido.'
    }

    $wslEnvironments = @(Get-PcSetupWslEnvironments -Configuration $configuration)
    foreach ($environment in $wslEnvironments) {
        $profile = Import-PcSetupWslProfile -Configuration $configuration -Environment $environment
        if ([bool]$profile.SetAsDefaultUser -ne [bool]$environment.Default) { throw "WSL $($environment.Name): Profile.SetAsDefaultUser deve coincidir com Environment.Default." }
    }
    foreach ($group in @($wslEnvironments | Where-Object Enabled | Group-Object WindowsAccount, Distribution)) {
        $defaults = @($group.Group | Where-Object Default)
        if ($defaults.Count -ne 1) { throw "Cada distribuicao WSL por conta deve ter exatamente um ambiente Default. Grupo: $($group.Name)" }
    }
    return $configuration
}

function Get-PcSetupVirtualizationAssessment {
    [CmdletBinding()]
    param(
        [string[]]$RequestedFeatures = @(),
        [bool]$FirmwareVirtualization,
        [bool]$SecondLevelAddressTranslation,
        [bool]$VmMonitorModeExtensions,
        [bool]$DataExecutionPrevention
    )

    $supportedFeatures = @('HyperV','WindowsSandbox','VirtualMachinePlatform','WSL')
    $requested = @($RequestedFeatures | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
    foreach ($feature in $requested) {
        if ($feature -notin $supportedFeatures) { throw "Recurso de virtualizacao desconhecido: $feature" }
    }

    $missing = @()
    if ($requested.Count -gt 0) {
        if (-not $FirmwareVirtualization) { $missing += 'virtualizacao de hardware exposta pelo firmware ou hipervisor' }
        if (-not $SecondLevelAddressTranslation) { $missing += 'SLAT' }
    }
    if (@($requested | Where-Object { $_ -in @('HyperV','WindowsSandbox') }).Count -gt 0) {
        if (-not $VmMonitorModeExtensions) { $missing += 'extensoes de monitor de VM' }
        if (-not $DataExecutionPrevention) { $missing += 'prevencao de execucao de dados' }
    }

    return [pscustomobject]@{
        Ready             = ($missing.Count -eq 0)
        RequestedFeatures = $requested
        Missing           = $missing
    }
}

function Resolve-PcSetupTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][hashtable]$Configuration,
        [string]$SystemRoot = $null
    )

    if ([string]::IsNullOrWhiteSpace($SystemRoot)) {
        $SystemRoot = [IO.Path]::GetPathRoot($env:SystemRoot)
    }
    $programData = $env:ProgramData
    if ([string]::IsNullOrWhiteSpace($programData)) { $programData = Join-Path $SystemRoot 'ProgramData' }
    $localAppData = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = Join-Path $SystemRoot 'Users\Default\AppData\Local' }
    $desktop = $env:PC_SETUP_CALLER_DESKTOP
    if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = [Environment]::GetFolderPath('Desktop') }
    if ([string]::IsNullOrWhiteSpace($desktop)) {
        $userProfile = $env:USERPROFILE
        if ([string]::IsNullOrWhiteSpace($userProfile)) { $userProfile = Join-Path $SystemRoot 'Users\Default' }
        $desktop = Join-Path $userProfile 'Desktop'
    }

    return $Value.
        Replace('{SystemRoot}', $SystemRoot.TrimEnd('\')).
        Replace('{ProgramData}', $programData.TrimEnd('\')).
        Replace('{LocalAppData}', $localAppData.TrimEnd('\')).
        Replace('{Desktop}', $desktop.TrimEnd('\')).
        Replace('{PrimaryUser}', [string]$Configuration.Machine.PrimaryUser)
}

function Get-PcSetupStorageInventory {
    [CmdletBinding()]
    param()

    $systemDriveLetter = $env:SystemDrive.TrimEnd(':')
    $systemPartition = Get-Partition -DriveLetter $systemDriveLetter -ErrorAction Stop
    $systemDisk = $systemPartition | Get-Disk -ErrorAction Stop

    $volumes = @()
    foreach ($volume in @(Get-Volume -ErrorAction Stop | Where-Object DriveLetter)) {
        try {
            $partition = Get-Partition -DriveLetter $volume.DriveLetter -ErrorAction Stop
            $disk = $partition | Get-Disk -ErrorAction Stop
            $isRemovable = ([string]$volume.DriveType -ne 'Fixed') -or ([string]$disk.BusType -in @('USB','SD','MMC'))
            $volumes += [pscustomobject]@{
                DriveLetter  = [string]$volume.DriveLetter
                Root         = ('{0}:\' -f $volume.DriveLetter)
                FileSystem   = [string]$volume.FileSystem
                Label        = [string]$volume.FileSystemLabel
                HealthStatus = [string]$volume.HealthStatus
                SizeGB       = [math]::Round($volume.Size / 1GB, 1)
                DiskNumber   = [int]$disk.Number
                DiskModel    = [string]$disk.FriendlyName
                BusType      = [string]$disk.BusType
                IsRemovable  = $isRemovable
            }
        }
        catch {
            Write-Warning "Nao foi possivel associar o volume $($volume.DriveLetter): a um disco: $($_.Exception.Message)"
        }
    }

    $disks = @(Get-Disk -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Number           = [int]$_.Number
            Model            = [string]$_.FriendlyName
            BusType          = [string]$_.BusType
            PartitionStyle   = [string]$_.PartitionStyle
            OperationalStatus = [string]$_.OperationalStatus
            HealthStatus     = [string]$_.HealthStatus
            SizeGB           = [math]::Round($_.Size / 1GB, 1)
            IsRemovable      = ([string]$_.BusType -in @('USB','SD','MMC'))
        }
    })

    return @{
        SystemRoot       = ('{0}:\' -f $systemDriveLetter)
        SystemDriveLetter = $systemDriveLetter
        SystemDiskNumber = [int]$systemDisk.Number
        Volumes          = $volumes
        Disks            = $disks
    }
}

function Select-PcSetupInteractiveVolume {
    param([Parameter(Mandatory)][object[]]$Candidates)

    Write-Host 'Volumes candidatos:' -ForegroundColor Cyan
    for ($index = 0; $index -lt $Candidates.Count; $index++) {
        $candidate = $Candidates[$index]
        Write-Host ("[{0}] {1}: {2} GB, {3}, {4}" -f ($index + 1), $candidate.DriveLetter, $candidate.SizeGB, $candidate.DiskModel, $candidate.FileSystem)
    }
    $selection = Read-Host 'Escolha o numero do volume de dados ou 0 para usar o disco do Windows'
    $number = 0
    if (-not [int]::TryParse($selection, [ref]$number) -or $number -lt 0 -or $number -gt $Candidates.Count) {
        throw 'Selecao de volume invalida.'
    }
    if ($number -eq 0) { return $null }
    return $Candidates[$number - 1]
}

function Resolve-PcSetupStorage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Configuration,
        [hashtable]$Inventory = $null,
        [string]$SelectedDataRoot = ''
    )

    if (-not $Inventory) { $Inventory = Get-PcSetupStorageInventory }
    $systemRoot = [IO.Path]::GetFullPath([string]$Inventory.SystemRoot)
    $dataConfiguration = $Configuration.Storage.Data
    $selectedVolume = $null
    $dataMode = 'SystemDirectory'
    $fallback = if ($dataConfiguration.ContainsKey('Root')) { [string]$dataConfiguration.Root } else { [string]$dataConfiguration.SingleDiskFallbackRoot }
    $fallbackRoot = [IO.Path]::GetFullPath((Resolve-PcSetupTemplate -Value $fallback -Configuration $Configuration -SystemRoot $systemRoot))

    if ($Configuration.Storage.System.RequireHealthy) {
        $systemVolume = $Inventory.Volumes | Where-Object { $_.DiskNumber -eq $Inventory.SystemDiskNumber -and $_.DriveLetter -eq $Inventory.SystemDriveLetter } | Select-Object -First 1
        if (-not $systemVolume) { throw 'O volume atual do Windows nao apareceu no inventario de armazenamento.' }
        if ($systemVolume.HealthStatus -ne 'Healthy') { throw "O volume atual do Windows nao esta Healthy: $($systemVolume.HealthStatus)." }
    }

    if ($dataConfiguration.Mode -eq 'Adaptive' -and $dataConfiguration.SecondaryDiskPolicy -ne 'Ignore') {
        $candidates = @($Inventory.Volumes | Where-Object {
            $_.DiskNumber -ne $Inventory.SystemDiskNumber -and
            ($dataConfiguration.AllowRemovableVolumes -or -not $_.IsRemovable) -and
            $_.FileSystem -eq 'NTFS'
        })

        if ($dataConfiguration.RequireHealthy) {
            $unhealthy = @($candidates | Where-Object { $_.HealthStatus -ne 'Healthy' })
            if ($unhealthy.Count -gt 0) {
                throw "Volume de dados candidato sem estado Healthy: $($unhealthy[0].DriveLetter): ($($unhealthy[0].HealthStatus))."
            }
        }

        if ($candidates.Count -gt 1 -and $dataConfiguration.OnMultipleCandidates -eq 'Stop') {
            throw 'Ha mais de um volume de dados candidato. Ajuste a configuracao antes de aplicar.'
        }

        if ($dataConfiguration.SecondaryDiskPolicy -eq 'UseIfAvailable') {
            if ($candidates.Count -eq 1) { $selectedVolume = $candidates[0] }
        }
        elseif ($dataConfiguration.SecondaryDiskPolicy -eq 'Ask') {
            if ($Configuration.Execution.Mode -ne 'Interactive') { throw 'A selecao Ask exige modo Interactive.' }
            if (-not [string]::IsNullOrWhiteSpace($SelectedDataRoot)) {
                $normalizedSelection = [IO.Path]::GetFullPath($SelectedDataRoot)
                if ($normalizedSelection.TrimEnd('\') -ne $fallbackRoot.TrimEnd('\')) {
                    $selectedVolume = $candidates | Where-Object { ([IO.Path]::GetFullPath([string]$_.Root)).TrimEnd('\') -eq $normalizedSelection.TrimEnd('\') } | Select-Object -First 1
                    if (-not $selectedVolume) { throw "A escolha de armazenamento do plano nao esta mais disponivel: $normalizedSelection" }
                }
            }
            elseif ($candidates.Count -gt 0) {
                $selectedVolume = Select-PcSetupInteractiveVolume -Candidates $candidates
            }
        }

        if (-not $selectedVolume -and $candidates.Count -eq 0) {
            $unpreparedDisks = @($Inventory.Disks | Where-Object {
                $_.Number -ne $Inventory.SystemDiskNumber -and
                ($dataConfiguration.AllowRemovableVolumes -or -not $_.IsRemovable)
            })
            if ($unpreparedDisks.Count -gt 0) {
                throw 'Existe um disco secundario, mas nenhum volume NTFS utilizavel. Prepare o disco no Gerenciamento de Disco e rode o plano novamente.'
            }
        }
    }

    if ($selectedVolume) {
        $dataRoot = [IO.Path]::GetFullPath([string]$selectedVolume.Root)
        $dataMode = 'DedicatedVolume'
    }
    else {
        $dataRoot = $fallbackRoot
        if ($dataRoot.TrimEnd('\') -eq $systemRoot.TrimEnd('\')) { throw 'A raiz de dados nao pode ser a raiz do volume do Windows.' }
    }

    return @{
        SystemRoot        = $systemRoot
        SystemDriveLetter = [string]$Inventory.SystemDriveLetter
        SystemDiskNumber  = [int]$Inventory.SystemDiskNumber
        DataRoot          = $dataRoot
        DataMode          = $dataMode
        DataVolume        = $selectedVolume
        Inventory         = $Inventory
    }
}

function Get-PcSetupConfiguredPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Configuration,
        [Parameter(Mandatory)][hashtable]$Storage
    )

    $base = [IO.Path]::GetFullPath([string]$Storage.DataRoot)
    $prefix = $base.TrimEnd('\') + '\'
    $paths = @{}
    $seen = @()
    foreach ($key in $Configuration.Storage.Paths.Keys) {
        $relative = Resolve-PcSetupTemplate -Value ([string]$Configuration.Storage.Paths[$key]) -Configuration $Configuration -SystemRoot $Storage.SystemRoot
        if ([IO.Path]::IsPathRooted($relative)) { throw "Storage.Paths.$key deve ser relativo." }
        $full = [IO.Path]::GetFullPath((Join-Path $base $relative))
        if ($full.TrimEnd('\') -eq $base.TrimEnd('\')) { throw "Storage.Paths.$key nao pode apontar para a propria raiz de dados." }
        if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Storage.Paths.$key sai da raiz de dados configurada."
        }
        if ($seen -contains $full.TrimEnd('\')) { throw "Storage.Paths.$key duplica outro caminho configurado." }
        $seen += $full.TrimEnd('\')
        $paths[$key] = $full
    }
    return $paths
}

function Get-PcSetupRuntimePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Configuration,
        [Parameter(Mandatory)][string]$Key,
        [string]$SystemRoot = $null
    )

    if (-not $Configuration.Runtime.ContainsKey($Key)) { throw "Runtime.$Key nao existe." }
    return [IO.Path]::GetFullPath((Resolve-PcSetupTemplate -Value ([string]$Configuration.Runtime[$Key]) -Configuration $Configuration -SystemRoot $SystemRoot))
}

function Resolve-PcSetupProjectPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Configuration,
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$SettingName
    )

    if ([IO.Path]::IsPathRooted($Value)) { throw "$SettingName deve ser um caminho relativo ao projeto." }
    $projectRoot = [IO.Path]::GetFullPath([string]$Configuration._ProjectRoot)
    $fullPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $Value))
    if (-not $fullPath.StartsWith($projectRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "$SettingName sai da raiz do projeto."
    }
    return $fullPath
}

function Get-PcSetupAccounts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Configuration)

    $accounts = @()
    foreach ($key in @('DailyUser','RecoveryAdmin','Public')) {
        $account = $Configuration.Accounts[$key]
        $accounts += [pscustomobject]@{
            Key         = $key
            Name        = [string]$account.Name
            Role        = [string]$account.Role
            Enabled     = [bool]$account.Enabled
            Description = if ($account.ContainsKey('Description')) { [string]$account.Description } else { "pc-setup $key" }
        }
    }
    return $accounts
}

function Get-PcSetupWslEnvironments {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Configuration)

    if (-not $Configuration.WSL.ContainsKey('Environments')) { return @() }
    $result = @()
    foreach ($name in @($Configuration.WSL.Environments.Keys | Sort-Object)) {
        $definition = $Configuration.WSL.Environments[$name]
        $account = $Configuration.Accounts[[string]$definition.AccountKey]
        $result += [pscustomobject]@{
            Name           = [string]$name
            Enabled        = [bool]$definition.Enabled
            AccountKey     = [string]$definition.AccountKey
            WindowsAccount = [string]$account.Name
            Distribution   = [string]$definition.Distribution
            Profile        = [string]$definition.Profile
            Default        = [bool]$definition.Default
        }
    }
    return $result
}

function Import-PcSetupWslProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Configuration,
        [Parameter(Mandatory)]$Environment
    )

    $path = Resolve-PcSetupProjectPath -Configuration $Configuration -Value ([string]$Environment.Profile) -SettingName "WSL.Environments.$($Environment.Name).Profile"
    $profile = Import-PowerShellDataFile -LiteralPath $path -ErrorAction Stop
    if (-not ($profile -is [hashtable])) { throw "O perfil WSL deve retornar uma hashtable: $path" }
    foreach ($key in @('SchemaVersion','LinuxUser','ProjectRoot','Packages','SetAsDefaultUser')) { Assert-PcSetupTableKey -Table $profile -Key $key -Path "WSL profile $($Environment.Name)" }
    if ($profile.SchemaVersion -ne '1.0') { throw "SchemaVersion WSL nao suportada em $path." }
    if ([string]$profile.LinuxUser -notmatch '^[a-z_][a-z0-9_-]{0,31}$') { throw "LinuxUser invalido em $path." }
    $projectRoot = ([string]$profile.ProjectRoot).Replace('{LinuxUser}', [string]$profile.LinuxUser)
    if (-not $projectRoot.StartsWith('/home/', [StringComparison]::Ordinal) -or $projectRoot -match '(^|/)\.\.(/|$)') { throw "ProjectRoot deve ficar em /home no perfil WSL: $path" }
    $packages = @()
    foreach ($package in @($profile.Packages)) {
        $name = [string]$package
        if ($name -notmatch '^[a-z0-9][a-z0-9+.-]*$') { throw "Pacote APT invalido no perfil WSL ${path}: $name" }
        if ($packages -contains $name) { throw "Pacote APT duplicado no perfil WSL ${path}: $name" }
        $packages += $name
    }
    $profile.ProjectRoot = $projectRoot
    $profile.Packages = $packages
    if (-not $profile.ContainsKey('RequireNoSudo')) { $profile.RequireNoSudo = $false }
    if (-not $profile.ContainsKey('SharedWith')) { $profile.SharedWith = @() }
    if (-not $profile.ContainsKey('SharedGroup')) { $profile.SharedGroup = '' }
    if (-not $profile.ContainsKey('ProjectRootMode')) { $profile.ProjectRootMode = '0755' }
    if ([string]$profile.ProjectRootMode -notmatch '^[0-7]{3,4}$') { throw "ProjectRootMode invalido no perfil WSL: $path" }
    if (-not [string]::IsNullOrWhiteSpace([string]$profile.SharedGroup) -and [string]$profile.SharedGroup -notmatch '^[a-z_][a-z0-9_-]{0,31}$') { throw "SharedGroup invalido no perfil WSL: $path" }
    $sharedUsers = @()
    foreach ($sharedUser in @($profile.SharedWith)) {
        $name = [string]$sharedUser
        if ($name -notmatch '^[a-z_][a-z0-9_-]{0,31}$') { throw "SharedWith invalido no perfil WSL ${path}: $name" }
        if ($sharedUsers -contains $name) { throw "SharedWith duplicado no perfil WSL ${path}: $name" }
        $sharedUsers += $name
    }
    if ($Configuration.Agent.Enabled -and $Environment.Name -eq [string]$Configuration.Agent.Environment) {
        $defaultEnvironment = Get-PcSetupWslEnvironments -Configuration $Configuration |
            Where-Object {
                $_.Enabled -and $_.Default -and
                $_.WindowsAccount -eq $Environment.WindowsAccount -and
                $_.Distribution -eq $Environment.Distribution
            } |
            Select-Object -First 1
        if (-not $defaultEnvironment) { throw "Ambiente WSL padrao ausente para compartilhar o workspace do agente: $path" }
        $defaultProfile = Import-PcSetupWslProfile -Configuration $Configuration -Environment $defaultEnvironment
        if ($sharedUsers -notcontains [string]$defaultProfile.LinuxUser) { $sharedUsers += [string]$defaultProfile.LinuxUser }
    }
    if ($sharedUsers.Count -gt 0 -and [string]::IsNullOrWhiteSpace([string]$profile.SharedGroup)) { throw "SharedGroup e obrigatorio quando SharedWith for usado: $path" }
    $profile.SharedWith = $sharedUsers
    if ($profile.ContainsKey('AiJail')) {
        if (-not ($profile.AiJail -is [hashtable])) { throw "AiJail deve ser uma hashtable no perfil WSL: $path" }
        foreach ($key in @('Enabled','Repository','Version','Architecture','Sha256','RequireAssetDigest')) { Assert-PcSetupTableKey -Table $profile.AiJail -Key $key -Path "WSL profile $($Environment.Name).AiJail" }
        if ($profile.AiJail.Enabled) {
            if ([string]$profile.AiJail.Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw "Repositorio do ai-jail invalido em $path." }
            if ([string]$profile.AiJail.Version -ne 'latest' -and [string]$profile.AiJail.Version -notmatch '^\d+\.\d+\.\d+$') { throw "Versao do ai-jail invalida em $path." }
            if ([string]$profile.AiJail.Architecture -notmatch '^[a-z0-9_]+$') { throw "Arquitetura do ai-jail invalida em $path." }
            if ($profile.AiJail.Version -ne 'latest' -and [string]$profile.AiJail.Sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw "Versao exata do ai-jail exige SHA-256 em $path." }
            if ($profile.AiJail.Version -eq 'latest' -and -not [string]::IsNullOrWhiteSpace([string]$profile.AiJail.Sha256)) { throw "AiJail.Sha256 deve ficar vazio com Version=latest em $path." }
            if ($profile.AiJail.RequireAssetDigest -ne $true) { throw "AiJail.RequireAssetDigest deve permanecer true em $path." }
            foreach ($requiredPackage in @('bubblewrap','ca-certificates','curl')) {
                if ($packages -notcontains $requiredPackage) { throw "O perfil ai-jail deve instalar o pacote APT $requiredPackage." }
            }
        }
    }
    if ($Configuration.Agent.Enabled -and $Environment.Name -eq [string]$Configuration.Agent.Environment -and $Configuration.Agent.Harness.Enabled) {
        foreach ($requiredPackage in @('nodejs','npm')) {
            if ($packages -notcontains $requiredPackage) { throw "O perfil do agente deve instalar o pacote APT $requiredPackage." }
        }
        $profile['Harness'] = @{
            Enabled        = [bool]$Configuration.Agent.Harness.Enabled
            PackageManager = [string]$Configuration.Agent.Harness.PackageManager
            Package        = [string]$Configuration.Agent.Harness.Package
            Version        = [string]$Configuration.Agent.Harness.Version
            Command        = [string]$Configuration.Agent.DefaultCommand
        }
    }
    if ($Configuration.Agent.Enabled -and $Environment.Name -eq [string]$Configuration.Agent.Environment -and $Configuration.Agent.Memory.Enabled) {
        foreach ($requiredPackage in @('ca-certificates','curl')) {
            if ($packages -notcontains $requiredPackage) { throw "O perfil do ai-memory deve instalar o pacote APT $requiredPackage." }
        }
        $profile['AiMemory'] = @{
            Enabled            = [bool]$Configuration.Agent.Memory.Enabled
            Repository         = [string]$Configuration.Agent.Memory.Repository
            Version            = [string]$Configuration.Agent.Memory.Version
            Architecture       = [string]$Configuration.Agent.Memory.Architecture
            Sha256             = [string]$Configuration.Agent.Memory.Sha256
            RequireAssetDigest = [bool]$Configuration.Agent.Memory.RequireAssetDigest
            Client             = [string]$Configuration.Agent.Memory.Client
            ProjectStrategy    = [string]$Configuration.Agent.Memory.ProjectStrategy
            ServerUrl          = [string]$Configuration.Agent.Memory.ServerUrl
        }
    }
    $profile['_ProfilePath'] = $path
    return $profile
}

function Get-PcSetupPackageDefinitions {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Configuration)

    $result = @()
    $seen = @()
    $versionLock = Get-PcSetupVersionLock -Configuration $Configuration
    foreach ($profile in @($Configuration.Packages.Profiles)) {
        $path = Join-Path $Configuration._ProjectRoot "config\packages\$profile.txt"
        if (-not (Test-Path -LiteralPath $path)) { throw "Perfil de pacotes nao encontrado: $path" }
        foreach ($line in @(Get-Content -LiteralPath $path)) {
            $entry = $line.Trim()
            if (-not $entry -or $entry.StartsWith('#')) { continue }
            $parts = $entry -split '\|', 3
            $id = $parts[0].Trim()
            $scope = if ($parts.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($parts[1])) { $parts[1].Trim().ToLowerInvariant() } else { [string]$Configuration.Packages.InstallScope }
            $criticality = if ($parts.Count -eq 3 -and -not [string]::IsNullOrWhiteSpace($parts[2])) { $parts[2].Trim().ToLowerInvariant() } else { [string]$Configuration.Packages.DefaultCriticality }
            if ($id -notmatch '^[A-Za-z0-9._-]+$') { throw "ID winget invalido em ${path}: $id" }
            if ($scope -notin @('machine','user')) { throw "Escopo winget invalido em ${path}: $scope" }
            if ($criticality -notin @('required','optional')) { throw "Criticidade winget invalida em ${path}: $criticality" }
            if ($seen -notcontains $id) {
                $lockedVersion = $null
                if ($versionLock) {
                    $lockedPackage = @($versionLock.Packages | Where-Object PackageId -eq $id)
                    if ($lockedPackage.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$lockedPackage[0].Version)) { throw "Versions.LockFile nao possui uma versao unica para $id." }
                    $lockedVersion = [string]$lockedPackage[0].Version
                }
                $result += [pscustomobject]@{ PackageId = $id; Scope = $scope; Criticality = $criticality; Required = $criticality -eq 'required'; Profile = [string]$profile; Version = $lockedVersion }
                $seen += $id
            }
        }
    }
    return $result
}

function Get-PcSetupVersionLock {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Configuration)

    if ([string]$Configuration.Versions.Mode -eq 'Latest') { return $null }
    $path = Resolve-PcSetupProjectPath -Configuration $Configuration -Value ([string]$Configuration.Versions.LockFile) -SettingName 'Versions.LockFile'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Arquivo de versoes fixadas ausente: $path" }
    try { $lock = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Arquivo de versoes fixadas invalido: $($_.Exception.Message)" }
    if ([string]$lock.SchemaVersion -ne '1.0') { throw 'SchemaVersion do arquivo de versoes fixadas nao suportada.' }
    $seen = @()
    foreach ($package in @($lock.Packages)) {
        if ([string]$package.PackageId -notmatch '^[A-Za-z0-9._-]+$' -or [string]::IsNullOrWhiteSpace([string]$package.Version)) { throw 'Arquivo de versoes fixadas contem pacote invalido.' }
        if ($seen -contains [string]$package.PackageId) { throw "Arquivo de versoes fixadas contem pacote duplicado: $($package.PackageId)" }
        $seen += [string]$package.PackageId
    }
    return $lock
}

function Get-PcSetupPackageIds {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Configuration)

    return @(Get-PcSetupPackageDefinitions -Configuration $Configuration | ForEach-Object PackageId)
}

function Write-PcSetupJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string]$Path
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $InputObject | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Path
}

function Assert-PcSetupCompletedApplyReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Configuration,
        [Parameter(Mandatory)][string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'A fase de usuario exige o relatorio concluido da mesma aplicacao do Windows.'
    }
    $report = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $configHash = (Get-FileHash -LiteralPath $Configuration._ConfigPath -Algorithm SHA256).Hash
    $projectHash = Get-PcSetupProjectFingerprint -Configuration $Configuration
    $completedAt = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$report.CompletedAt, [ref]$completedAt)) { throw 'O relatorio de aplicacao nao possui data de conclusao valida.' }
    $receiptAge = [datetimeoffset]::Now - $completedAt
    if ($report.Status -ne 'Completed' -or $report.ConfigSha256 -ne $configHash -or $report.ProjectSha256 -ne $projectHash -or
        -not $report.Recovery -or $report.Recovery.Validated -ne $true -or -not $report.Recovery.SequenceNumber -or
        $receiptAge.TotalHours -lt 0 -or $receiptAge.TotalHours -gt [int]$Configuration.Recovery.UserPhaseReceiptMaxAgeHours) {
        throw 'O relatorio informado nao comprova uma aplicacao Windows concluida e protegida para esta configuracao.'
    }
    return $report
}

function Get-PcSetupProjectFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Configuration)

    $files = @(
        (Join-Path $Configuration._ProjectRoot 'bootstrap.ps1'),
        (Join-Path $Configuration._ProjectRoot 'verify.ps1'),
        $Configuration._ConfigPath,
        (Resolve-PcSetupProjectPath -Configuration $Configuration -Value ([string]$Configuration.Packages.OfflineManifest) -SettingName 'Packages.OfflineManifest')
    )
    $files += @(Get-ChildItem -LiteralPath (Join-Path $Configuration._ProjectRoot 'scripts') -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psm1') } | ForEach-Object FullName)
    $wslRoot = Join-Path $Configuration._ProjectRoot 'wsl'
    if (Test-Path -LiteralPath $wslRoot -PathType Container) {
        $files += @(Get-ChildItem -LiteralPath $wslRoot -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psd1','.sh','.cmd') } | ForEach-Object FullName)
    }
    foreach ($profile in @($Configuration.Packages.Profiles)) {
        $files += Join-Path $Configuration._ProjectRoot "config\packages\$profile.txt"
    }
    if ([string]$Configuration.Versions.Mode -eq 'Locked') {
        $files += Resolve-PcSetupProjectPath -Configuration $Configuration -Value ([string]$Configuration.Versions.LockFile) -SettingName 'Versions.LockFile'
    }

    $records = foreach ($file in @($files | Sort-Object -Unique)) {
        $resolved = (Resolve-Path -LiteralPath $file -ErrorAction Stop).Path
        '{0}|{1}' -f $resolved.ToLowerInvariant(), (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($records -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

Export-ModuleMember -Function Get-PcSetupExecutionMode, Test-PcSetupAdministrator, Assert-PcSetupAdministrator, Import-PcSetupConfiguration, Get-PcSetupVirtualizationAssessment, Resolve-PcSetupTemplate, Get-PcSetupStorageInventory, Resolve-PcSetupStorage, Get-PcSetupConfiguredPaths, Get-PcSetupRuntimePath, Resolve-PcSetupProjectPath, Get-PcSetupAccounts, Get-PcSetupWslEnvironments, Import-PcSetupWslProfile, Get-PcSetupPackageDefinitions, Get-PcSetupPackageIds, Get-PcSetupVersionLock, Write-PcSetupJson, Assert-PcSetupCompletedApplyReport, Get-PcSetupProjectFingerprint
