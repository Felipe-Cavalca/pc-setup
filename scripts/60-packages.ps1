#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\machine.psd1'),
    [switch]$Plan,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$coreModule = Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1'
$recoveryModule = Join-Path $PSScriptRoot 'lib\PcSetup.Recovery.psm1'
$wingetModule = Join-Path $PSScriptRoot 'lib\PcSetup.Winget.psm1'
Import-Module $coreModule -Force
Import-Module $recoveryModule -Force
Import-Module $wingetModule -Force

$mode = Get-PcSetupExecutionMode -Plan:$Plan -Apply:$Apply
$configuration = Import-PcSetupConfiguration -Path $Config
if (-not $configuration.Packages.Enabled) {
    Write-Host '[IGNORADO] Instalacao de pacotes desabilitada na configuracao.'
    return [pscustomobject]@{ Step = 'Packages'; Mode = $mode; Enabled = $false; Items = @() }
}

$packageIds = @(Get-PcSetupPackageIds -Configuration $configuration)
$manifestPath = Resolve-PcSetupProjectPath -Configuration $configuration -Value ([string]$configuration.Packages.OfflineManifest) -SettingName 'Packages.OfflineManifest'
$offlineManifest = Import-PowerShellDataFile -LiteralPath $manifestPath -ErrorAction Stop
if ($offlineManifest.SchemaVersion -ne '1.0') { throw 'SchemaVersion do manifesto offline nao suportada.' }
$offlineInstallers = @($offlineManifest.Installers)
$offlineIds = @()
foreach ($entry in $offlineInstallers) {
    foreach ($key in @('PackageId','File','Sha256','Arguments')) {
        if (-not $entry.ContainsKey($key)) { throw "Entrada offline sem $key no manifesto." }
    }
    if ([string]::IsNullOrWhiteSpace([string]$entry.PackageId) -or [string]::IsNullOrWhiteSpace([string]$entry.File)) { throw 'PackageId e File nao podem ficar vazios no manifesto offline.' }
    if ($offlineIds -contains [string]$entry.PackageId) { throw "PackageId offline duplicado: $($entry.PackageId)" }
    $offlineIds += [string]$entry.PackageId
}

if ($mode -eq 'Plan') {
    $items = foreach ($id in $packageIds) {
        $offline = $null -ne ($offlineInstallers | Where-Object { $_.PackageId -eq $id } | Select-Object -First 1)
        Write-Host "[PLANO] Instalar/atualizar $id via Winget. Fallback offline: $offline."
        [pscustomobject]@{ PackageId = $id; Online = $true; OfflineFallback = $offline; Action = 'InstallOrUpdate' }
    }
    return [pscustomobject]@{ Step = 'Packages'; Mode = $mode; Enabled = $true; Items = @($items) }
}

Assert-PcSetupAdministrator
$null = Enter-PcSetupProtectedScript -EntryPoint $MyInvocation.MyCommand.Name
if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw 'Winget nao encontrado. Atualize o App Installer pela Microsoft Store e tente novamente.'
}

function Invoke-WingetOnline {
    param([Parameter(Mandatory)][string]$PackageId, [int]$RetryCount)

    & winget.exe list --id $PackageId --exact --disable-interactivity | Out-Host
    $isInstalled = $LASTEXITCODE -eq 0
    $operation = if ($isInstalled) { 'upgrade' } else { 'install' }
    $attempt = 0
    do {
        $attempt++
        Write-Host "[WINGET] $operation $PackageId (tentativa $attempt de $($RetryCount + 1))" -ForegroundColor Cyan
        & winget.exe $operation --id $PackageId --exact --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-Host
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) { return [pscustomobject]@{ Success = $true; Operation = $operation; ExitCode = 0; Status = 'Success' } }
        if ($isInstalled -and $exitCode -eq -1978335189) {
            return [pscustomobject]@{ Success = $true; Operation = $operation; ExitCode = $exitCode; Status = 'PresentNoApplicableUpgrade' }
        }
        if ($attempt -le $RetryCount) { Write-Warning "Winget falhou para $PackageId com codigo $LASTEXITCODE; repetindo." }
    } while ($attempt -le $RetryCount)
    return [pscustomobject]@{ Success = $false; Operation = $operation; ExitCode = $exitCode; Status = 'Failed' }
}

function Invoke-OfflineInstaller {
    param([Parameter(Mandatory)][string]$PackageId)

    $entry = $offlineInstallers | Where-Object { $_.PackageId -eq $PackageId } | Select-Object -First 1
    if (-not $entry) { throw "Winget falhou e nao ha fallback offline configurado para $PackageId." }
    if ([string]::IsNullOrWhiteSpace([string]$entry.Sha256) -or [string]$entry.Sha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw "SHA-256 offline invalido para $PackageId."
    }

    $installerRoot = Resolve-PcSetupProjectPath -Configuration $configuration -Value ([string]$configuration.Packages.OfflineInstallerDirectory) -SettingName 'Packages.OfflineInstallerDirectory'
    $installerPath = [IO.Path]::GetFullPath((Join-Path $installerRoot ([string]$entry.File)))
    if (-not $installerPath.StartsWith($installerRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "O instalador offline de $PackageId sai da pasta permitida."
    }
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) { throw "Instalador offline ausente: $installerPath" }
    $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
    if ($actualHash -ne ([string]$entry.Sha256).ToUpperInvariant()) { throw "SHA-256 divergente para o instalador offline de $PackageId." }

    Write-Host "[OFFLINE] Instalando $PackageId com arquivo validado." -ForegroundColor Yellow
    $process = Start-Process -FilePath $installerPath -ArgumentList @($entry.Arguments) -Wait -PassThru
    if ($process.ExitCode -notin @(0, 1641, 3010)) { throw "Instalador offline de $PackageId terminou com codigo $($process.ExitCode)." }
    return $process.ExitCode
}

$results = @()
foreach ($id in $packageIds) {
    $online = Invoke-WingetOnline -PackageId $id -RetryCount ([int]$configuration.Packages.RetryCount)
    if ($online.Success) {
        $results += [pscustomobject]@{ PackageId = $id; Source = 'winget'; Operation = $online.Operation; Status = $online.Status; ExitCode = $online.ExitCode }
        continue
    }
    if (-not $configuration.Packages.AllowOfflineFallback) { throw "Winget falhou para $id e o fallback offline esta desabilitado." }
    $exitCode = Invoke-OfflineInstaller -PackageId $id
    $results += [pscustomobject]@{ PackageId = $id; Source = 'offline'; Status = 'Success'; ExitCode = $exitCode }
}

$configHash = (Get-FileHash -LiteralPath $configuration._ConfigPath -Algorithm SHA256).Hash
$projectHash = Get-PcSetupProjectFingerprint -Configuration $configuration
$inventory = Get-PcSetupWingetInstalledInventory -PackageIds $packageIds -ConfigSha256 $configHash -ProjectSha256 $projectHash -RequireAll
$inventoryPath = Get-PcSetupRuntimePath -Configuration $configuration -Key 'WingetInventoryPath'
$reportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'ReportDirectory'
$archivePath = Join-Path $reportDirectory ('winget-installed-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
Write-PcSetupJson -InputObject $inventory -Path $inventoryPath | Out-Null
Write-PcSetupJson -InputObject $inventory -Path $archivePath | Out-Null
Write-Host "[RELATORIO] Versoes instaladas pelo Winget: $inventoryPath" -ForegroundColor Green

[pscustomobject]@{ Step = 'Packages'; Mode = $mode; Enabled = $true; Items = $results; InventoryPath = $inventoryPath; InventoryArchive = $archivePath; Inventory = $inventory }
