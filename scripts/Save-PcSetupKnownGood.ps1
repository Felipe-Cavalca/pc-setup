#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [switch]$ExportLock
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path $root 'config\machine.psd1' }
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $root 'wsl\PcSetup.Wsl.psm1') -Force
$configuration = Import-PcSetupConfiguration -Path $Config
$knownGoodPath = Get-PcSetupRuntimePath -Configuration $configuration -Key 'KnownGoodVersionPath'

if ($ExportLock) {
    if (-not (Test-Path -LiteralPath $knownGoodPath -PathType Leaf)) { throw "Snapshot de versoes conhecidas ausente: $knownGoodPath. Conclua ATUALIZAR.cmd primeiro." }
    $knownGood = Get-Content -LiteralPath $knownGoodPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$knownGood.SchemaVersion -ne '1.0' -or $knownGood.Status -ne 'KnownGood') { throw 'O snapshot conhecido nao e valido para exportacao.' }
    $configuredPackageIds = @(Get-PcSetupPackageDefinitions -Configuration $configuration | ForEach-Object PackageId)
    $missingPackages = @($configuredPackageIds | Where-Object {
        $id = $_
        $null -eq ($knownGood.Packages | Where-Object { $_.PackageId -eq $id -and $_.Found -and -not [string]::IsNullOrWhiteSpace([string]$_.Version) } | Select-Object -First 1)
    })
    if ($missingPackages.Count -gt 0) { throw "Nao e possivel fixar um estado incompleto. Pacotes sem versao: $($missingPackages -join ', ')." }
    $lockPath = Resolve-PcSetupProjectPath -Configuration $configuration -Value ([string]$configuration.Versions.LockFile) -SettingName 'Versions.LockFile'
    $lock = [ordered]@{
        SchemaVersion = '1.0'
        GeneratedAt   = (Get-Date).ToString('o')
        Packages      = @($knownGood.Packages | Where-Object Found | ForEach-Object { [ordered]@{ PackageId = $_.PackageId; Version = $_.Version; Scope = $_.Scope } })
        WSL           = @($knownGood.WSL)
    }
    Write-PcSetupJson -InputObject $lock -Path $lockPath | Out-Null
    Write-Host "[OK] Versoes conhecidas exportadas para $lockPath." -ForegroundColor Green
    Write-Host "Para reproduzi-las em uma instalacao limpa, altere Versions.Mode para 'Locked'." -ForegroundColor Yellow
    [pscustomobject]@{ Action = 'ExportLock'; Path = $lockPath; Packages = @($lock.Packages).Count }
    exit 0
}

$inventoryPath = Get-PcSetupRuntimePath -Configuration $configuration -Key 'WingetInventoryPath'
if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) { throw "Inventario Winget ausente: $inventoryPath" }
$inventory = Get-Content -LiteralPath $inventoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$configHash = (Get-FileHash -LiteralPath $configuration._ConfigPath -Algorithm SHA256).Hash
$projectHash = Get-PcSetupProjectFingerprint -Configuration $configuration
if ([string]$inventory.SchemaVersion -ne '1.0' -or $inventory.ConfigSha256 -ne $configHash -or $inventory.ProjectSha256 -ne $projectHash) {
    throw 'O inventario Winget nao corresponde a configuracao e ao projeto atuais.'
}
$wslStates = @()
if ($configuration.Features.WSL -and (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    $installedDistributions = @(Get-PcSetupWslDistributionNames)
    foreach ($environment in @(Get-PcSetupWslEnvironments -Configuration $configuration | Where-Object { $_.Enabled -and $_.WindowsAccount -eq $env:USERNAME })) {
        if ($installedDistributions -notcontains $environment.Distribution) { continue }
        $state = Get-PcSetupWslInstalledState -Distribution $environment.Distribution -ProfileName $environment.Name
        $wslStates += [ordered]@{
            Environment = $environment.Name; Distribution = $environment.Distribution
            Metadata = $state.Metadata; Packages = $state.Packages
        }
    }
}
$snapshot = [ordered]@{
    SchemaVersion = '1.0'; GeneratedAt = (Get-Date).ToString('o'); Status = 'KnownGood'
    Profile = $configuration.ProfileName; WingetVersion = $inventory.WingetVersion
    ConfigSha256 = $configHash; ProjectSha256 = $projectHash
    Packages = @($inventory.Packages); WSL = $wslStates
}
Write-PcSetupJson -InputObject $snapshot -Path $knownGoodPath | Out-Null
Write-Host "[RELATORIO] Versoes conhecidas e validadas: $knownGoodPath" -ForegroundColor Green
[pscustomobject]@{ Action = 'CaptureKnownGood'; Path = $knownGoodPath; Packages = @($snapshot.Packages).Count; WSLEnvironments = $wslStates.Count }
