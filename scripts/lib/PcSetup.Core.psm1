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

    foreach ($key in @('SchemaVersion','ProfileName','Execution','Windows','Machine','Storage','Accounts','Features','Packages','WSL','Personalization','Debloat','Recovery','Security','Runtime')) {
        Assert-PcSetupTableKey -Table $configuration -Key $key -Path 'config'
    }
    $requiredKeys = @{
        Execution      = @('Mode','OnMissingSetting','CollectSecretsBeforeApply','StoreSecretsInRepository')
        Windows        = @('Edition','TargetVersion','MinimumBuild')
        Machine        = @('ComputerName','PrimaryUser')
        Features       = @('HyperV','WindowsSandbox','VirtualMachinePlatform','WSL','PublicVirtualMachine')
        Packages       = @('Enabled','PreferredSource','PreferCurrentVersion','Profiles','AllowOfflineFallback','OfflineInstallerDirectory','OfflineManifest','RetryCount')
        WSL            = @('Update','DefaultVersion','Distribution')
        Personalization = @('Enabled','WallpaperPath')
        Debloat        = @('Enabled','Mode','Repository','Release','ArchiveSha256','RequireSha256','RequireConfirmation')
        Recovery       = @('RequireRestorePointBeforeChanges','Scope','SystemProtectionMustBeEnabled','EnableSystemProtectionAutomatically','FailIfRestorePointUnavailable','AllowExistingRestorePointReuse','AllowSameApplySessionReuse','ProtectDirectScriptExecution')
        Security       = @('DailyUserMustBeStandard','BackupAclBeforeChanges','ManageBitLocker','BitLockerMode','ReportBitLockerStatus','RequireRecoveryKeyCheck','DemoteDailyUserAutomatically')
        Runtime        = @('StateDirectory','ReportDirectory','StopOnError','RequirePlanBeforeApply')
    }
    foreach ($section in $requiredKeys.Keys) {
        foreach ($key in $requiredKeys[$section]) { Assert-PcSetupTableKey -Table $configuration[$section] -Key $key -Path "config.$section" }
    }
    foreach ($key in @('System','Data','Paths')) { Assert-PcSetupTableKey -Table $configuration.Storage -Key $key -Path 'config.Storage' }
    foreach ($key in @('Selection','RequireHealthy')) { Assert-PcSetupTableKey -Table $configuration.Storage.System -Key $key -Path 'config.Storage.System' }
    foreach ($key in @('Mode','SecondaryDiskPolicy','OnMultipleCandidates','AllowRemovableVolumes','RequireHealthy')) { Assert-PcSetupTableKey -Table $configuration.Storage.Data -Key $key -Path 'config.Storage.Data' }

    if ($configuration.SchemaVersion -ne '1.0') { throw "SchemaVersion nao suportada: $($configuration.SchemaVersion)" }
    if ($configuration.Execution.Mode -notin @('Unattended','Interactive')) { throw 'Execution.Mode deve ser Unattended ou Interactive.' }
    if ($configuration.Execution.OnMissingSetting -ne 'Stop' -or -not $configuration.Execution.CollectSecretsBeforeApply) { throw 'Configuracoes ausentes devem interromper e segredos devem ser coletados antes das alteracoes dependentes.' }
    if ($configuration.Execution.StoreSecretsInRepository -ne $false) { throw 'StoreSecretsInRepository deve permanecer false.' }
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
    if ($configuration.WSL.DefaultVersion -notin @(1, 2)) { throw 'WSL.DefaultVersion deve ser 1 ou 2.' }
    if ($configuration.Packages.PreferredSource -ne 'winget' -or -not $configuration.Packages.PreferCurrentVersion) { throw 'Pacotes devem usar Winget e preferir a versao atual.' }
    if ([int]$configuration.Packages.RetryCount -lt 0 -or [int]$configuration.Packages.RetryCount -gt 5) { throw 'Packages.RetryCount deve ficar entre 0 e 5.' }
    if ([string]::IsNullOrWhiteSpace([string]$configuration.Packages.OfflineManifest)) { throw 'Packages.OfflineManifest nao pode ficar vazio.' }
    if (-not $configuration.Runtime.StopOnError -or -not $configuration.Runtime.RequirePlanBeforeApply) { throw 'Runtime deve interromper em erro e exigir plano antes da aplicacao.' }
    if ($configuration.Debloat.Mode -ne 'ReviewThenApply' -or -not $configuration.Debloat.RequireConfirmation) { throw 'Debloat deve permanecer em modo ReviewThenApply com confirmacao.' }
    if ([string]::IsNullOrWhiteSpace([string]$configuration.Machine.PrimaryUser)) { throw 'Machine.PrimaryUser nao pode ficar vazio.' }
    if (-not [string]::IsNullOrWhiteSpace([string]$configuration.Machine.ComputerName) -and [string]$configuration.Machine.ComputerName -notmatch '^(?!-)[A-Za-z0-9-]{1,15}(?<!-)$') {
        throw 'Machine.ComputerName deve ter ate 15 caracteres, usando letras, numeros ou hifen sem hifen nas extremidades.'
    }
    if (-not $configuration.Accounts.DailyUser.Enabled -or -not $configuration.Accounts.RecoveryAdmin.Enabled) {
        throw 'DailyUser e RecoveryAdmin devem permanecer habilitados.'
    }
    if ([string]$configuration.Machine.PrimaryUser -ne [string]$configuration.Accounts.DailyUser.Name) {
        throw 'Machine.PrimaryUser deve ser igual a Accounts.DailyUser.Name.'
    }

    $accountNames = @()
    foreach ($accountKey in @('DailyUser','RecoveryAdmin','Codex','God','Public')) {
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

    foreach ($profile in @($configuration.Packages.Profiles)) {
        if ($profile -notmatch '^[a-z0-9-]+$') { throw "Nome de perfil de pacotes invalido: $profile" }
    }

    if ($configuration.Debloat.Enabled -and $configuration.Debloat.RequireSha256 -and ([string]$configuration.Debloat.ArchiveSha256 -notmatch '^[a-fA-F0-9]{64}$')) {
        throw 'Debloat habilitado exige ArchiveSha256 valido.'
    }

    $configuration['_ConfigPath'] = $resolvedPath
    $configuration['_ProjectRoot'] = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    return $configuration
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

    return $Value.
        Replace('{SystemRoot}', $SystemRoot.TrimEnd('\')).
        Replace('{ProgramData}', $programData.TrimEnd('\')).
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
        [hashtable]$Inventory = $null
    )

    if (-not $Inventory) { $Inventory = Get-PcSetupStorageInventory }
    $systemRoot = [IO.Path]::GetFullPath([string]$Inventory.SystemRoot)
    $dataConfiguration = $Configuration.Storage.Data
    $selectedVolume = $null
    $dataMode = 'SystemDirectory'

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
            $selectedVolume = Select-PcSetupInteractiveVolume -Candidates $candidates
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
        $fallback = if ($dataConfiguration.ContainsKey('Root')) { [string]$dataConfiguration.Root } else { [string]$dataConfiguration.SingleDiskFallbackRoot }
        $dataRoot = [IO.Path]::GetFullPath((Resolve-PcSetupTemplate -Value $fallback -Configuration $Configuration -SystemRoot $systemRoot))
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
    foreach ($key in @('DailyUser','RecoveryAdmin','Codex','God','Public')) {
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

function Get-PcSetupPackageIds {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Configuration)

    $result = @()
    foreach ($profile in @($Configuration.Packages.Profiles)) {
        $path = Join-Path $Configuration._ProjectRoot "config\packages\$profile.txt"
        if (-not (Test-Path -LiteralPath $path)) { throw "Perfil de pacotes nao encontrado: $path" }
        foreach ($line in @(Get-Content -LiteralPath $path)) {
            $id = $line.Trim()
            if (-not $id -or $id.StartsWith('#')) { continue }
            if ($id -notmatch '^[A-Za-z0-9._-]+$') { throw "ID winget invalido em ${path}: $id" }
            if ($result -notcontains $id) { $result += $id }
        }
    }
    return $result
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

function Get-PcSetupProjectFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Configuration)

    $files = @(
        (Join-Path $Configuration._ProjectRoot 'bootstrap.ps1'),
        $Configuration._ConfigPath,
        (Resolve-PcSetupProjectPath -Configuration $Configuration -Value ([string]$Configuration.Packages.OfflineManifest) -SettingName 'Packages.OfflineManifest')
    )
    $files += @(Get-ChildItem -LiteralPath (Join-Path $Configuration._ProjectRoot 'scripts') -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psm1') } | ForEach-Object FullName)
    foreach ($profile in @($Configuration.Packages.Profiles)) {
        $files += Join-Path $Configuration._ProjectRoot "config\packages\$profile.txt"
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

Export-ModuleMember -Function Get-PcSetupExecutionMode, Test-PcSetupAdministrator, Assert-PcSetupAdministrator, Import-PcSetupConfiguration, Resolve-PcSetupTemplate, Get-PcSetupStorageInventory, Resolve-PcSetupStorage, Get-PcSetupConfiguredPaths, Get-PcSetupRuntimePath, Resolve-PcSetupProjectPath, Get-PcSetupAccounts, Get-PcSetupPackageIds, Write-PcSetupJson, Get-PcSetupProjectFingerprint
