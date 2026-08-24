#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [string]$WindowsApplyReport = '',
    [switch]$Plan,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\machine.psd1' }
$coreModule = Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1'
$wingetModule = Join-Path $PSScriptRoot 'lib\PcSetup.Winget.psm1'
Import-Module $coreModule -Force
Import-Module $wingetModule -Force

$mode = Get-PcSetupExecutionMode -Plan:$Plan -Apply:$Apply
$configuration = Import-PcSetupConfiguration -Path $Config
if (-not $configuration.Packages.Enabled) {
    Write-Host '[IGNORADO] Instalacao de pacotes desabilitada na configuracao.'
    return [pscustomobject]@{ Step = 'Packages'; Mode = $mode; Enabled = $false; Items = @() }
}

$packageDefinitions = @(Get-PcSetupPackageDefinitions -Configuration $configuration)
$packageIds = @($packageDefinitions | ForEach-Object PackageId)
$installScopes = @{}
foreach ($definition in $packageDefinitions) { $installScopes[$definition.PackageId] = [string]$definition.Scope }
$manifestPath = Resolve-PcSetupProjectPath -Configuration $configuration -Value ([string]$configuration.Packages.OfflineManifest) -SettingName 'Packages.OfflineManifest'
$offlineManifest = Import-PowerShellDataFile -LiteralPath $manifestPath -ErrorAction Stop
if ($offlineManifest.SchemaVersion -ne '1.0') { throw 'SchemaVersion do manifesto offline nao suportada.' }
$offlineInstallers = @($offlineManifest.Installers)
$offlineIds = @()
foreach ($entry in $offlineInstallers) {
    foreach ($key in @('PackageId','File','Sha256','Arguments','Scope')) {
        if (-not $entry.ContainsKey($key)) { throw "Entrada offline sem $key no manifesto." }
    }
    if ([string]::IsNullOrWhiteSpace([string]$entry.PackageId) -or [string]::IsNullOrWhiteSpace([string]$entry.File)) { throw 'PackageId e File nao podem ficar vazios no manifesto offline.' }
    if ([string]$entry.Scope -notin @('machine','user')) { throw "Escopo offline invalido para $($entry.PackageId)." }
    if ($offlineIds -contains [string]$entry.PackageId) { throw "PackageId offline duplicado: $($entry.PackageId)" }
    $offlineIds += [string]$entry.PackageId
}

if ($mode -eq 'Plan') {
    $items = foreach ($definition in $packageDefinitions) {
        $id = [string]$definition.PackageId
        $installScope = [string]$definition.Scope
        $offline = $null -ne ($offlineInstallers | Where-Object { $_.PackageId -eq $id } | Select-Object -First 1)
        Write-Host "[PLANO] Instalar/atualizar $id via Winget no escopo $installScope. Fallback offline: $offline."
        [pscustomobject]@{ PackageId = $id; Online = $true; Scope = $installScope; OfflineFallback = $offline; Action = 'InstallOrUpdate' }
    }
    return [pscustomobject]@{ Step = 'Packages'; Mode = $mode; Enabled = $true; Items = @($items) }
}

if ($env:USERNAME -ne [string]$configuration.Accounts.DailyUser.Name) {
    throw "Os pacotes devem ser aplicados na sessao da conta diaria $($configuration.Accounts.DailyUser.Name). Usuario atual: $env:USERNAME."
}
$null = Assert-PcSetupCompletedApplyReport -Configuration $configuration -Path $WindowsApplyReport
if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw 'Winget nao encontrado. Atualize o App Installer pela Microsoft Store e tente novamente.'
}

Write-Host '[WINGET] Atualizando a fonte winget da conta diaria.' -ForegroundColor Cyan
& winget.exe source update --name winget --disable-interactivity | Out-Host
$sourceUpdateExitCode = $LASTEXITCODE
$wingetSourceReady = $sourceUpdateExitCode -eq 0
if ($sourceUpdateExitCode -ne 0) {
    Write-Warning "A fonte winget nao pode ser atualizada (codigo $sourceUpdateExitCode). Os fallbacks offline configurados serao avaliados."
}

function Invoke-WingetOnline {
    param([Parameter(Mandatory)][string]$PackageId, [Parameter(Mandatory)][string]$Scope, [int]$RetryCount)

    $wingetNoApplicationsFound = -1978335212
    $wingetCommandRequiresAdmin = -1978335207
    $wingetNoApplicableUpgrade = -1978335189

    if (-not $wingetSourceReady) {
        return [pscustomobject]@{ Success = $false; Operation = 'source-update'; ExitCode = $sourceUpdateExitCode; Status = 'SourceUnavailable' }
    }

    & winget.exe list --id $PackageId --exact --source winget --scope $Scope --accept-source-agreements --disable-interactivity | Out-Host
    $listExitCode = $LASTEXITCODE
    if ($listExitCode -notin @(0, $wingetNoApplicationsFound)) {
        return [pscustomobject]@{ Success = $false; Operation = 'list'; ExitCode = $listExitCode; Status = 'SourceQueryFailed' }
    }
    $isInstalled = $listExitCode -eq 0
    $operation = if ($isInstalled) { 'upgrade' } else { 'install' }
    $attempt = 0
    do {
        $attempt++
        Write-Host "[WINGET] $operation $PackageId (tentativa $attempt de $($RetryCount + 1))" -ForegroundColor Cyan
        & winget.exe $operation --id $PackageId --exact --source winget --scope $Scope --silent --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-Host
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) { return [pscustomobject]@{ Success = $true; Operation = $operation; ExitCode = 0; Status = 'Success' } }
        if ($isInstalled -and $exitCode -eq $wingetNoApplicableUpgrade) {
            return [pscustomobject]@{ Success = $true; Operation = $operation; ExitCode = $exitCode; Status = 'PresentNoApplicableUpgrade' }
        }
        if ($exitCode -eq $wingetCommandRequiresAdmin) {
            Write-Warning "O manifesto de $PackageId exige o Winget em contexto administrativo. O pc-setup preserva o Winget na conta diaria e avaliara o fallback offline."
            return [pscustomobject]@{ Success = $false; Operation = $operation; ExitCode = $exitCode; Status = 'RequiresAdministrator' }
        }
        if ($attempt -le $RetryCount) { Write-Warning "Winget falhou para $PackageId com codigo $exitCode; repetindo." }
    } while ($attempt -le $RetryCount)
    return [pscustomobject]@{ Success = $false; Operation = $operation; ExitCode = $exitCode; Status = 'Failed' }
}

function Invoke-OfflineInstaller {
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][string]$OnlineStatus,
        [Parameter(Mandatory)][int]$OnlineExitCode
    )

    $entry = $offlineInstallers | Where-Object { $_.PackageId -eq $PackageId } | Select-Object -First 1
    if (-not $entry) { throw "Winget falhou para $PackageId (status $OnlineStatus, codigo $OnlineExitCode) e nao ha fallback offline configurado." }
    if ([string]$entry.Scope -ne $Scope) { throw "O fallback offline de $PackageId nao corresponde ao escopo $Scope." }
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
    $startArguments = @{ FilePath = $installerPath; ArgumentList = @($entry.Arguments); Wait = $true; PassThru = $true }
    if ($Scope -eq 'machine') { $startArguments.Verb = 'RunAs' }
    $process = Start-Process @startArguments
    if ($process.ExitCode -notin @(0, 1641, 3010)) { throw "Instalador offline de $PackageId terminou com codigo $($process.ExitCode)." }
    return $process.ExitCode
}

$results = @()
foreach ($definition in $packageDefinitions) {
    $id = [string]$definition.PackageId
    $installScope = [string]$definition.Scope
    $online = Invoke-WingetOnline -PackageId $id -Scope $installScope -RetryCount ([int]$configuration.Packages.RetryCount)
    if ($online.Success) {
        $results += [pscustomobject]@{ PackageId = $id; Source = 'winget'; Scope = $installScope; Operation = $online.Operation; Status = $online.Status; ExitCode = $online.ExitCode }
        continue
    }
    if (-not $configuration.Packages.AllowOfflineFallback) { throw "Winget falhou para $id (status $($online.Status), codigo $($online.ExitCode)) e o fallback offline esta desabilitado." }
    $exitCode = Invoke-OfflineInstaller -PackageId $id -Scope $installScope -OnlineStatus $online.Status -OnlineExitCode $online.ExitCode
    $results += [pscustomobject]@{ PackageId = $id; Source = 'offline'; Scope = $installScope; Status = 'Success'; ExitCode = $exitCode }
}

$configHash = (Get-FileHash -LiteralPath $configuration._ConfigPath -Algorithm SHA256).Hash
$projectHash = Get-PcSetupProjectFingerprint -Configuration $configuration
$inventory = Get-PcSetupWingetInstalledInventory -PackageIds $packageIds -ConfigSha256 $configHash -ProjectSha256 $projectHash -InstallScopes $installScopes -RequireAll
$inventoryPath = Get-PcSetupRuntimePath -Configuration $configuration -Key 'WingetInventoryPath'
$reportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'UserReportDirectory'
$archivePath = Join-Path $reportDirectory ('winget-installed-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
Write-PcSetupJson -InputObject $inventory -Path $inventoryPath | Out-Null
Write-PcSetupJson -InputObject $inventory -Path $archivePath | Out-Null
Write-Host "[RELATORIO] Versoes instaladas pelo Winget: $inventoryPath" -ForegroundColor Green

[pscustomobject]@{ Step = 'Packages'; Mode = $mode; Enabled = $true; Items = $results; InventoryPath = $inventoryPath; InventoryArchive = $archivePath; Inventory = $inventory }
