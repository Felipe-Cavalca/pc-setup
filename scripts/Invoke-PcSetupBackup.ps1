#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [ValidateSet('Create','Export','Verify','RestoreTest')][string]$Action = 'Create',
    [string]$Destination = '',
    [string]$SnapshotPath = '',
    [switch]$Plan
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path $root 'config\machine.psd1' }
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Backup.psm1') -Force
$configuration = Import-PcSetupConfiguration -Path $Config
if (-not $configuration.Backup.Enabled) { throw 'O backup esta desabilitado na configuracao.' }
if ($env:USERNAME -ne [string]$configuration.Accounts.DailyUser.Name) { throw "Execute o backup na conta diaria $($configuration.Accounts.DailyUser.Name)." }

$configHash = (Get-FileHash -LiteralPath $configuration._ConfigPath -Algorithm SHA256).Hash
$systemRoot = [IO.Path]::GetPathRoot($env:SystemRoot)
$reportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'ReportDirectory' -SystemRoot $systemRoot
$applyReportFile = Get-ChildItem -LiteralPath $reportDirectory -Filter 'pc-setup-apply-*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $applyReportFile) { throw 'Nenhum relatorio de aplicacao foi encontrado. Execute INSTALAR.cmd ou ATUALIZAR.cmd primeiro.' }
$applyReport = Get-Content -LiteralPath $applyReportFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
if ($applyReport.Status -ne 'Completed' -or $applyReport.ConfigSha256 -ne $configHash) { throw 'O relatorio mais recente nao corresponde a uma aplicacao concluida desta configuracao.' }
$storage = Resolve-PcSetupStorage -Configuration $configuration -SelectedDataRoot ([string]$applyReport.Storage.DataRoot)
$paths = Get-PcSetupConfiguredPaths -Configuration $configuration -Storage $storage
$stagingRoot = [IO.Path]::GetFullPath([string]$paths[[string]$configuration.Backup.StagingPathKey]).TrimEnd('\')

function Get-ConfiguredBackupSources {
    $sources = @()
    foreach ($sourceKey in @($configuration.Backup.SourcePathKeys)) {
        $key = [string]$sourceKey
        $sources += [pscustomobject]@{
            Key            = $key
            Path           = [string]$paths[$key]
            TargetRelative = $key
            Type           = 'StoragePath'
            Kind           = 'Directory'
            Required       = $true
        }
    }
    foreach ($folderName in @($configuration.Backup.UserProfileFolders)) {
        $sources += [pscustomobject]@{
            Key            = "WindowsProfile/$folderName"
            Path           = Join-Path $env:USERPROFILE ([string]$folderName)
            TargetRelative = Join-Path 'WindowsProfile' ([string]$folderName)
            Type           = 'WindowsProfile'
            Kind           = 'Directory'
            Required       = $true
        }
    }
    if ($configuration.Backup.IncludeSetupInventory) {
        foreach ($inventory in @(
            @{ Key = 'WingetInventory'; RuntimeKey = 'WingetInventoryPath'; FileName = 'winget-installed.json' },
            @{ Key = 'KnownGoodVersions'; RuntimeKey = 'KnownGoodVersionPath'; FileName = 'versions-known-good.json' }
        )) {
            $sources += [pscustomobject]@{
                Key            = [string]$inventory.Key
                Path           = Get-PcSetupRuntimePath -Configuration $configuration -Key ([string]$inventory.RuntimeKey)
                TargetRelative = Join-Path 'SetupInventory' ([string]$inventory.FileName)
                Type           = 'SetupInventory'
                Kind           = 'File'
                Required       = $false
            }
        }
    }
    return $sources
}

function Get-LatestSnapshot {
    $item = Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'backup-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $item) { throw "Nenhum snapshot foi encontrado em $stagingRoot." }
    return $item.FullName
}

if ($Action -eq 'Create') {
    $snapshotName = 'backup-' + (Get-Date -Format 'yyyy-MM-dd_HHmmss')
    $snapshot = Join-Path $stagingRoot $snapshotName
    $configuredSources = @(Get-ConfiguredBackupSources)
    if ($Plan) {
        [pscustomobject]@{ Action = 'Create'; SnapshotPath = $snapshot; Sources = $configuredSources; Hashes = [bool]$configuration.Backup.VerifyHashes; AutomaticDeletion = $false }
        exit 0
    }
    if (Test-Path -LiteralPath $snapshot) { throw "O snapshot ja existe: $snapshot" }
    New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
    $sources = @()
    try {
        foreach ($configuredSource in $configuredSources) {
            $source = [string]$configuredSource.Path
            $expectedPathType = if ([string]$configuredSource.Kind -eq 'File') { 'Leaf' } else { 'Container' }
            if (-not (Test-Path -LiteralPath $source -PathType $expectedPathType)) {
                if ([bool]$configuredSource.Required) { throw "Origem de backup ausente: $source" }
                Write-Warning "Inventario opcional ainda nao existe e foi ignorado: $source"
                $sources += [pscustomobject]@{ Key = [string]$configuredSource.Key; Type = [string]$configuredSource.Type; OriginalPath = $source; Status = 'MissingOptional' }
                continue
            }
            $target = Join-Path $snapshot ([string]$configuredSource.TargetRelative)
            if ([string]$configuredSource.Kind -eq 'File') {
                $targetParent = Split-Path -Parent $target
                New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
                Copy-Item -LiteralPath $source -Destination $target -Force
                $sources += [pscustomobject]@{ Key = [string]$configuredSource.Key; Type = [string]$configuredSource.Type; OriginalPath = $source; Status = 'Copied' }
            }
            else {
                $copyExitCode = Invoke-PcSetupRobocopy -Source $source -Destination $target
                $sources += [pscustomobject]@{ Key = [string]$configuredSource.Key; Type = [string]$configuredSource.Type; OriginalPath = $source; CopyExitCode = $copyExitCode; Status = 'Copied' }
            }
        }
        $files = if ($configuration.Backup.VerifyHashes) { @(Get-PcSetupBackupFileRecords -SnapshotPath $snapshot) } else { @() }
        $manifest = [ordered]@{
            SchemaVersion = '1.0'; CreatedAt = (Get-Date).ToString('o'); Profile = $configuration.ProfileName
            SnapshotName = $snapshotName; DataRoot = $storage.DataRoot; Sources = $sources; HashesEnabled = [bool]$configuration.Backup.VerifyHashes; Files = $files
        }
        Write-PcSetupJson -InputObject $manifest -Path (Join-Path $snapshot 'manifest.json') | Out-Null
        if ($configuration.Backup.VerifyHashes) { $null = Test-PcSetupBackupManifest -SnapshotPath $snapshot }
    }
    catch { throw "O snapshot incompleto foi preservado para diagnostico em $snapshot. $($_.Exception.Message)" }
    Write-Host "[OK] Snapshot local criado e verificado: $snapshot" -ForegroundColor Green
    Write-Host 'Ele ainda esta no mesmo armazenamento dos dados. Copie-o para uma unidade externa com EXPORTAR-BACKUP.cmd.' -ForegroundColor Yellow
    [pscustomobject]@{ Action = 'Create'; Status = 'Completed'; SnapshotPath = $snapshot; Files = $files.Count }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($SnapshotPath)) { $SnapshotPath = Get-LatestSnapshot }
$SnapshotPath = [IO.Path]::GetFullPath($SnapshotPath)
if ($Action -eq 'Verify') {
    $result = Test-PcSetupBackupManifest -SnapshotPath $SnapshotPath
    Write-Host "[OK] Backup verificado: $SnapshotPath ($($result.Files) arquivo(s))." -ForegroundColor Green
    $result
    exit 0
}

if ($Action -eq 'RestoreTest') {
    if (-not $configuration.Backup.RestoreTest.Enabled) { throw 'O teste de restauracao esta desabilitado na configuracao.' }
    if ([string]::IsNullOrWhiteSpace($Destination)) {
        $Destination = Resolve-PcSetupTemplate -Value ([string]$configuration.Backup.RestoreTest.Destination) -Configuration $configuration -SystemRoot $systemRoot
    }
    if ([string]::IsNullOrWhiteSpace($Destination) -or -not [IO.Path]::IsPathRooted($Destination)) { throw 'Backup.RestoreTest.Destination deve resultar em um caminho absoluto.' }
    $restoreRoot = [IO.Path]::GetFullPath($Destination)
    if ($Plan) {
        [pscustomobject]@{
            Action = 'RestoreTest'; SnapshotPath = $SnapshotPath; DestinationRoot = $restoreRoot
            VerifyHashes = $true; KeepRestoredCopy = [bool]$configuration.Backup.RestoreTest.KeepRestoredCopy
        }
        exit 0
    }
    $result = Invoke-PcSetupRestoreTest -SnapshotPath $SnapshotPath -DestinationRoot $restoreRoot -KeepRestoredCopy ([bool]$configuration.Backup.RestoreTest.KeepRestoredCopy)
    $userReportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'UserReportDirectory' -SystemRoot $systemRoot
    $restoreReportPath = Join-Path $userReportDirectory ('restore-test-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    $restoreReport = [ordered]@{
        SchemaVersion = '1.0'; GeneratedAt = (Get-Date).ToString('o'); Status = 'Completed'
        SnapshotPath = $result.SnapshotPath; RestoredPath = $result.RestoredPath; Files = $result.Files
        RemovedAfterVerification = $result.RemovedAfterVerification
    }
    Write-PcSetupJson -InputObject $restoreReport -Path $restoreReportPath | Out-Null
    Write-Host "[OK] Restauracao testada com $($result.Files) arquivo(s). Relatorio: $restoreReportPath" -ForegroundColor Green
    if ($result.RemovedAfterVerification) { Write-Host 'A copia temporaria validada foi removida; o snapshot original permaneceu intacto.' -ForegroundColor Cyan }
    $result
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Destination)) { $Destination = [string]$configuration.Backup.ExternalDestination }
if ([string]::IsNullOrWhiteSpace($Destination)) { $Destination = Read-Host 'Pasta de destino na unidade externa ou em uma pasta sincronizada' }
if ([string]::IsNullOrWhiteSpace($Destination) -or -not [IO.Path]::IsPathRooted($Destination)) { throw 'Informe um caminho absoluto para exportar o backup.' }
$destinationRoot = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
$destinationVolume = [IO.Path]::GetPathRoot($destinationRoot)
if (-not (Test-Path -LiteralPath $destinationVolume -PathType Container)) { throw "A unidade de destino nao esta conectada: $destinationVolume" }
if ($destinationRoot.StartsWith($storage.DataRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or $destinationRoot.TrimEnd('\') -eq $storage.DataRoot.TrimEnd('\')) {
    throw 'A exportacao deve usar outro armazenamento, nao a mesma raiz de dados.'
}
$exportRoot = Join-Path $destinationRoot 'pc-setup-backups'
$exportSnapshot = Join-Path $exportRoot (Split-Path -Leaf $SnapshotPath)
if ($Plan) {
    [pscustomobject]@{ Action = 'Export'; Source = $SnapshotPath; Destination = $exportSnapshot; VerifyHashes = $true; AutomaticDeletion = $false }
    exit 0
}
$null = Test-PcSetupBackupManifest -SnapshotPath $SnapshotPath
if (Test-Path -LiteralPath $exportSnapshot) { throw "O destino ja existe e nao sera sobrescrito: $exportSnapshot" }
$null = Invoke-PcSetupRobocopy -Source $SnapshotPath -Destination $exportSnapshot
$verified = Test-PcSetupBackupManifest -SnapshotPath $exportSnapshot
Write-Host "[OK] Backup exportado e verificado: $exportSnapshot ($($verified.Files) arquivo(s))." -ForegroundColor Green
[pscustomobject]@{ Action = 'Export'; Status = 'Completed'; Source = $SnapshotPath; Destination = $exportSnapshot; Files = $verified.Files }
