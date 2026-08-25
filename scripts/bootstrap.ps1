#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [switch]$Plan,
    [switch]$Apply,
    [switch]$IncludeDebloat,
    [switch]$ConfirmDebloatReviewed
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path $root 'config\machine.psd1' }
$coreModule = Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1'
$recoveryModule = Join-Path $PSScriptRoot 'lib\PcSetup.Recovery.psm1'
$planSummaryModule = Join-Path $PSScriptRoot 'lib\PcSetup.PlanSummary.psm1'
Import-Module $coreModule -Force
Import-Module $recoveryModule -Force
Import-Module $planSummaryModule -Force

$mode = Get-PcSetupExecutionMode -Plan:$Plan -Apply:$Apply
Assert-PcSetupAdministrator
$configuration = Import-PcSetupConfiguration -Path $Config
$includeConfiguredDebloat = [bool]($IncludeDebloat -and $configuration.Debloat.Enabled)
if ($mode -eq 'Apply' -and $PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Use o Windows PowerShell 5.1 para -Apply; o cmdlet de ponto de restauracao nao e suportado pelo PowerShell 7.'
}
if ($mode -eq 'Apply' -and $includeConfiguredDebloat -and $configuration.Debloat.RequireConfirmation -and -not $ConfirmDebloatReviewed) {
    throw 'O debloat da instalacao exige a confirmacao do plano. Execute INSTALAR.cmd e confirme com S.'
}
$computerInfo = Get-ComputerInfo -Property WindowsProductName -ErrorAction Stop
$windowsRegistry = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
$editionOk = [string]$windowsRegistry.EditionID -eq [string]$configuration.Windows.Edition
if (-not $editionOk) { throw "Edicao do Windows incompativel. EditionID esperado: $($configuration.Windows.Edition). Encontrado: $($windowsRegistry.EditionID) ($($computerInfo.WindowsProductName))." }
if ([int]$windowsRegistry.CurrentBuildNumber -lt [int]$configuration.Windows.MinimumBuild) { throw "Build do Windows abaixo da minima configurada: $($windowsRegistry.CurrentBuildNumber) < $($configuration.Windows.MinimumBuild)." }
if (-not [string]::IsNullOrWhiteSpace([string]$configuration.Windows.TargetVersion) -and [string]$windowsRegistry.DisplayVersion -ne [string]$configuration.Windows.TargetVersion) {
    throw "Versao do Windows incompativel. Esperada: $($configuration.Windows.TargetVersion). Encontrada: $($windowsRegistry.DisplayVersion)."
}
$configHash = (Get-FileHash -LiteralPath $configuration._ConfigPath -Algorithm SHA256).Hash
$projectHash = Get-PcSetupProjectFingerprint -Configuration $configuration
$systemRoot = [IO.Path]::GetPathRoot($env:SystemRoot)
$stateDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'StateDirectory' -SystemRoot $systemRoot
$reportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'ReportDirectory' -SystemRoot $systemRoot
$planReceiptPath = Join-Path $stateDirectory 'last-plan.json'
$applyStatePath = Join-Path $stateDirectory 'apply-state.json'
$receipt = $null
$selectedDataRoot = ''
if ($mode -eq 'Apply' -and $configuration.Runtime.RequirePlanBeforeApply) {
    if (-not (Test-Path -LiteralPath $planReceiptPath -PathType Leaf)) { throw 'Gere um novo plano pelo launcher da raiz antes de aplicar.' }
    $receipt = Get-Content -Raw -LiteralPath $planReceiptPath | ConvertFrom-Json
    if ($receipt.ConfigSha256 -ne $configHash -or $receipt.ProjectSha256 -ne $projectHash -or [bool]$receipt.IncludeDebloat -ne $includeConfiguredDebloat) {
        throw 'O projeto, a configuracao ou a escolha do debloat mudou desde o ultimo plano. Gere um novo plano pelo launcher da raiz.'
    }
    $selectedDataRoot = [string]$receipt.DataRoot
}
$storage = Resolve-PcSetupStorage -Configuration $configuration -SelectedDataRoot $selectedDataRoot

function Invoke-PcSetupStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$RelativeScript,
        [Parameter(Mandatory)][hashtable]$Arguments
    )

    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    $scriptPath = Join-Path $root $RelativeScript
    return & $scriptPath @Arguments
}

function Get-PcSetupBootMarker {
    return (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o')
}

function Write-RunReport {
    param([Parameter(Mandatory)]$Report)

    $name = 'pc-setup-{0}-{1}.json' -f $mode.ToLowerInvariant(), (Get-Date -Format 'yyyyMMdd-HHmmss')
    $path = Join-Path $reportDirectory $name
    Write-PcSetupJson -InputObject $Report -Path $path | Out-Null
    Write-Host "`n[RELATORIO] $path" -ForegroundColor Green
    return $path
}

Write-Host '=== pc-setup ===' -ForegroundColor Cyan
Write-Host "Modo: $mode"
Write-Host "Perfil: $($configuration.ProfileName)"
Write-Host "Windows: $($storage.SystemRoot)"
Write-Host "Dados: $($storage.DataRoot) ($($storage.DataMode))"

$baseReport = [ordered]@{
    StartedAt    = (Get-Date).ToString('o')
    Mode         = $mode
    Profile      = $configuration.ProfileName
    ConfigPath   = $configuration._ConfigPath
    ConfigSha256 = $configHash
    ProjectSha256 = $projectHash
    Windows      = @{
        ProductName    = $computerInfo.WindowsProductName
        EditionID      = $windowsRegistry.EditionID
        DisplayVersion = $windowsRegistry.DisplayVersion
        Build          = [int]$windowsRegistry.CurrentBuildNumber
    }
    Storage      = @{
        SystemRoot = $storage.SystemRoot
        DataRoot   = $storage.DataRoot
        DataMode   = $storage.DataMode
        DataVolume = $storage.DataVolume
    }
    Recovery     = $null
    Steps        = @()
    Status       = 'Running'
    CompletedAt  = $null
    Error        = $null
}

if ($mode -eq 'Plan') {
    $common = @{ Config = $configuration._ConfigPath; Plan = $true }
    $baseReport.Steps += Invoke-PcSetupStep -Name 'Identidade da maquina' -RelativeScript 'scripts\05-machine.ps1' -Arguments $common
    $baseReport.Steps += Invoke-PcSetupStep -Name 'Recursos do Windows' -RelativeScript 'scripts\10-windows-features.ps1' -Arguments $common
    $baseReport.Steps += Invoke-PcSetupStep -Name 'Diretorios' -RelativeScript 'scripts\20-directories.ps1' -Arguments @{ Config = $configuration._ConfigPath; Storage = $storage; Plan = $true }
    $baseReport.Steps += Invoke-PcSetupStep -Name 'Usuarios locais' -RelativeScript 'scripts\30-users.ps1' -Arguments $common
    $baseReport.Steps += Invoke-PcSetupStep -Name 'Permissoes NTFS' -RelativeScript 'scripts\40-permissions.ps1' -Arguments @{ Config = $configuration._ConfigPath; Storage = $storage; Plan = $true }
    $baseReport.Steps += Invoke-PcSetupStep -Name 'Integracoes de armazenamento' -RelativeScript 'scripts\45-storage-integrations.ps1' -Arguments @{ Config = $configuration._ConfigPath; Storage = $storage; Plan = $true }
    $baseReport.Steps += Invoke-PcSetupStep -Name 'Pacotes' -RelativeScript 'scripts\60-packages.ps1' -Arguments $common
    $baseReport.Steps += Invoke-PcSetupStep -Name 'WSL' -RelativeScript 'scripts\70-wsl.ps1' -Arguments $common
    $baseReport.Steps += Invoke-PcSetupStep -Name 'Personalizacao' -RelativeScript 'scripts\80-personalization.ps1' -Arguments $common
    if ($includeConfiguredDebloat) {
        $baseReport.Steps += Invoke-PcSetupStep -Name 'Debloat' -RelativeScript 'scripts\50-debloat-akita.ps1' -Arguments $common
    }
    $baseReport.Status = 'Planned'
    $baseReport.CompletedAt = (Get-Date).ToString('o')
    $reportPath = Write-RunReport -Report $baseReport
    $readableReports = @()
    if ($configuration.PlanSummary.Enabled) {
        $planOutputDirectory = Resolve-PcSetupTemplate -Value ([string]$configuration.PlanSummary.OutputDirectory) -Configuration $configuration -SystemRoot $systemRoot
        $planOutputDirectory = [IO.Path]::GetFullPath($planOutputDirectory)
        $planSummary = Write-PcSetupPlanSummaryFiles -Plan $baseReport -JsonPath $reportPath -OutputDirectory $planOutputDirectory -FileBaseName ([string]$configuration.PlanSummary.FileBaseName) -Formats @($configuration.PlanSummary.Formats)
        $readableReports = @($planSummary.Files)
        Write-Host "[PLANO LEGIVEL] $($readableReports -join ', ')" -ForegroundColor Green
    }

    $receipt = @{
        CreatedAt    = (Get-Date).ToString('o')
        ConfigPath   = $configuration._ConfigPath
        ConfigSha256 = $configHash
        ProjectSha256 = $projectHash
        DataRoot     = $storage.DataRoot
        IncludeDebloat = $includeConfiguredDebloat
        ReportPath   = $reportPath
        ReadableReports = $readableReports
    }
    Write-PcSetupJson -InputObject $receipt -Path $planReceiptPath | Out-Null
    Write-Host "`nPlano concluido sem alterar configuracoes do Windows." -ForegroundColor Green
    Write-Host 'Leia o relatorio. Se estiver correto, execute novamente trocando -Plan por -Apply.'
    return
}

if ($configuration.Runtime.RequirePlanBeforeApply) {
    if ($receipt.ConfigSha256 -ne $configHash -or $receipt.ProjectSha256 -ne $projectHash -or $receipt.DataRoot -ne $storage.DataRoot -or [bool]$receipt.IncludeDebloat -ne $includeConfiguredDebloat) {
        throw 'O projeto, a configuracao, o armazenamento ou a escolha do debloat mudou desde o ultimo plano. Gere um novo plano pelo launcher da raiz.'
    }
}

$sessionStarted = $false
$isResume = $false
try {
    if (Test-Path -LiteralPath $applyStatePath -PathType Leaf) {
        $applyState = Get-Content -Raw -LiteralPath $applyStatePath | ConvertFrom-Json
        if ($applyState.ConfigSha256 -ne $configHash -or $applyState.ProjectSha256 -ne $projectHash -or $applyState.DataRoot -ne $storage.DataRoot -or [bool]$applyState.IncludeDebloat -ne $includeConfiguredDebloat) {
            throw 'Existe uma aplicacao incompleta com outra configuracao. Nao remova o estado sem revisar o relatorio anterior.'
        }
        if (-not $configuration.Recovery.AllowSameApplySessionReuse) { throw 'A retomada da mesma aplicacao esta desabilitada na configuracao.' }
        $restorePoint = Resume-PcSetupChangeSession -Description $applyState.RestorePoint.Description -SequenceNumber ([string]$applyState.RestorePoint.SequenceNumber) -SessionId $applyState.RestorePoint.SessionId
        $sessionStarted = $true
        $isResume = $true
        if ($applyState.Stage -eq 'RestartRequired' -and $applyState.BootMarker -eq (Get-PcSetupBootMarker)) {
            throw 'Os recursos foram habilitados, mas o Windows ainda nao foi reiniciado. Reinicie e execute o mesmo comando -Apply.'
        }
        Write-Host '[RETOMADA] Continuando a aplicacao incompleta.' -ForegroundColor Yellow
    }
    else {
        $restorePoint = Start-PcSetupChangeSession -EntryPoint $MyInvocation.MyCommand.Name
        $sessionStarted = $true
        $applyState = [ordered]@{
            StartedAt    = (Get-Date).ToString('o')
            Stage        = 'Starting'
            ConfigPath   = $configuration._ConfigPath
            ConfigSha256 = $configHash
            ProjectSha256 = $projectHash
            DataRoot     = $storage.DataRoot
            IncludeDebloat = $includeConfiguredDebloat
            BootMarker   = Get-PcSetupBootMarker
            RestorePoint = @{
                Description    = $restorePoint.Description
                SequenceNumber = $restorePoint.SequenceNumber
                SessionId      = $restorePoint.SessionId
            }
        }
        Write-PcSetupJson -InputObject $applyState -Path $applyStatePath | Out-Null
    }

    $baseReport.Recovery = @{
        Description    = $restorePoint.Description
        SequenceNumber = $restorePoint.SequenceNumber
        SessionId      = $restorePoint.SessionId
        Validated      = $true
        Resumed        = $isResume
    }

    if (-not $isResume -or $applyState.Stage -in @('Starting', 'RestartRequired')) {
        $machine = Invoke-PcSetupStep -Name 'Identidade da maquina' -RelativeScript 'scripts\05-machine.ps1' -Arguments @{ Config = $configuration._ConfigPath; Apply = $true }
        $baseReport.Steps += $machine
        $features = Invoke-PcSetupStep -Name 'Recursos do Windows' -RelativeScript 'scripts\10-windows-features.ps1' -Arguments @{ Config = $configuration._ConfigPath; Apply = $true }
        $baseReport.Steps += $features
        if ($machine.RestartRequired -or $features.RestartRequired) {
            $applyState.Stage = 'RestartRequired'
            $applyState.BootMarker = Get-PcSetupBootMarker
            Write-PcSetupJson -InputObject $applyState -Path $applyStatePath | Out-Null
            $baseReport.Status = 'RestartRequired'
            $baseReport.CompletedAt = (Get-Date).ToString('o')
            Write-RunReport -Report $baseReport | Out-Null
            Write-Host "`n[REINICIO NECESSARIO] Reinicie o Windows e execute exatamente o mesmo comando -Apply." -ForegroundColor Yellow
            return
        }
    }

    $applyState.Stage = 'Applying'
    Write-PcSetupJson -InputObject $applyState -Path $applyStatePath | Out-Null

    $passwords = @{}
    foreach ($account in @(Get-PcSetupAccounts -Configuration $configuration | Where-Object Enabled)) {
        if (-not (Get-LocalUser -Name $account.Name -ErrorAction SilentlyContinue)) {
            $passwords[$account.Name] = Read-Host "Defina a senha inicial para $($account.Name)" -AsSecureString
        }
    }

    $baseReport.Steps += Invoke-PcSetupStep -Name 'Diretorios' -RelativeScript 'scripts\20-directories.ps1' -Arguments @{ Config = $configuration._ConfigPath; Storage = $storage; Apply = $true }
    $baseReport.Steps += Invoke-PcSetupStep -Name 'Usuarios locais' -RelativeScript 'scripts\30-users.ps1' -Arguments @{ Config = $configuration._ConfigPath; AccountPasswords = $passwords; Apply = $true }
    $baseReport.Steps += Invoke-PcSetupStep -Name 'Permissoes NTFS' -RelativeScript 'scripts\40-permissions.ps1' -Arguments @{ Config = $configuration._ConfigPath; Storage = $storage; Apply = $true }
    $baseReport.Steps += Invoke-PcSetupStep -Name 'Integracoes de armazenamento' -RelativeScript 'scripts\45-storage-integrations.ps1' -Arguments @{ Config = $configuration._ConfigPath; Storage = $storage; Apply = $true }
    $baseReport.Steps += Invoke-PcSetupStep -Name 'WSL' -RelativeScript 'scripts\70-wsl.ps1' -Arguments @{ Config = $configuration._ConfigPath; Apply = $true }
    if ($includeConfiguredDebloat) {
        $baseReport.Steps += Invoke-PcSetupStep -Name 'Debloat' -RelativeScript 'scripts\50-debloat-akita.ps1' -Arguments @{ Config = $configuration._ConfigPath; Apply = $true; ConfirmReviewed = $true }
    }
    $baseReport.Status = 'Completed'
    $baseReport.CompletedAt = (Get-Date).ToString('o')
    Write-RunReport -Report $baseReport | Out-Null
    Remove-Item -LiteralPath $applyStatePath -Force
    Write-Host "`nSetup base concluido. O launcher executara a verificacao final." -ForegroundColor Green
}
catch {
    $baseReport.Status = 'Failed'
    $baseReport.CompletedAt = (Get-Date).ToString('o')
    $baseReport.Error = $_.Exception.Message
    try { Write-RunReport -Report $baseReport | Out-Null } catch { Write-Warning "Nao foi possivel gravar o relatorio de falha: $($_.Exception.Message)" }
    throw
}
finally {
    if ($sessionStarted) { Stop-PcSetupChangeSession }
}
