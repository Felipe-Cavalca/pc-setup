#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [ValidateSet('INSTALAR.cmd','ATUALIZAR.cmd')]
    [string]$LauncherName = 'ATUALIZAR.cmd'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path $root 'config\machine.psd1' }
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$startPath = Join-Path $PSScriptRoot 'Start-PcSetup.ps1'
$wslBootstrapPath = Join-Path $root 'wsl\bootstrap.ps1'
$wslVerifyPath = Join-Path $root 'wsl\verify.ps1'
$machineSummaryPath = Join-Path $root 'scripts\New-PcSetupMachineSummary.ps1'
$operation = if ($LauncherName -eq 'INSTALAR.cmd') { 'Instalacao' } else { 'Atualizacao' }
$executionLog = $null
$currentStage = 'Inicializacao'

function Write-PcSetupSessionEvent {
    param(
        [Parameter(Mandatory)][ValidateSet('Started','Info','Pending','Succeeded','Failed')][string]$Status,
        [Parameter(Mandatory)][string]$Message,
        [string]$Command = '',
        [object[]]$Arguments = @(),
        [System.Collections.IDictionary]$Data
    )

    if ($null -eq $script:executionLog) { return }
    try {
        Write-PcSetupExecutionEvent -Log $script:executionLog -Stage $script:currentStage -Status $Status -Message $Message -Command $Command -Arguments $Arguments -Data $Data | Out-Null
    }
    catch {
        Write-Warning "Nao foi possivel atualizar o log da sessao: $($_.Exception.Message)"
    }
}

function Get-CompletedWindowsApplyReport {
    param([Parameter(Mandatory)][hashtable]$Configuration)

    $systemRoot = [IO.Path]::GetPathRoot($env:SystemRoot)
    $stateDirectory = Get-PcSetupRuntimePath -Configuration $Configuration -Key 'StateDirectory' -SystemRoot $systemRoot
    if (Test-Path -LiteralPath (Join-Path $stateDirectory 'apply-state.json') -PathType Leaf) { return $null }
    $reportDirectory = Get-PcSetupRuntimePath -Configuration $Configuration -Key 'ReportDirectory' -SystemRoot $systemRoot
    $reportFile = Get-ChildItem -LiteralPath $reportDirectory -Filter 'pc-setup-apply-*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $reportFile) { return $null }
    try { $report = Assert-PcSetupCompletedApplyReport -Configuration $Configuration -Path $reportFile.FullName }
    catch { return $null }
    return [pscustomobject]@{ Path = $reportFile.FullName; Report = $report }
}

function Get-PcSetupWindowsFailureDiagnostic {
    param(
        [Parameter(Mandatory)][hashtable]$Configuration,
        [Parameter(Mandatory)][datetime]$NotBefore
    )

    $systemRoot = [IO.Path]::GetPathRoot($env:SystemRoot)
    $stateDirectory = Get-PcSetupRuntimePath -Configuration $Configuration -Key 'StateDirectory' -SystemRoot $systemRoot
    $lastErrorPath = Join-Path $stateDirectory 'last-error.json'
    if (Test-Path -LiteralPath $lastErrorPath -PathType Leaf) {
        $lastErrorFile = Get-Item -LiteralPath $lastErrorPath
        if ($lastErrorFile.LastWriteTime -ge $NotBefore.AddSeconds(-5)) {
            try {
                $diagnostic = Get-Content -LiteralPath $lastErrorPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if (-not [string]::IsNullOrWhiteSpace([string]$diagnostic.Message)) {
                    return [pscustomobject]@{ Message = [string]$diagnostic.Message; Path = $lastErrorPath }
                }
            }
            catch { }
        }
    }

    $reportDirectory = Get-PcSetupRuntimePath -Configuration $Configuration -Key 'ReportDirectory' -SystemRoot $systemRoot
    foreach ($reportFile in @(Get-ChildItem -LiteralPath $reportDirectory -Filter 'verify-*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $NotBefore.AddSeconds(-5) } |
        Sort-Object LastWriteTime -Descending)) {
        try {
            $report = Get-Content -LiteralPath $reportFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $failedChecks = @($report.Checks | Where-Object Status -eq 'FAIL')
            if ($failedChecks.Count -gt 0) {
                $failedDetails = @($failedChecks | ForEach-Object { "$($_.Name): $($_.Detail)" })
                $message = "A validacao final encontrou $($failedChecks.Count) falha(s):`n- $($failedDetails -join "`n- ")"
                return [pscustomobject]@{ Message = $message; Path = $reportFile.FullName }
            }
        }
        catch { }
    }

    foreach ($reportFile in @(Get-ChildItem -LiteralPath $reportDirectory -Filter 'pc-setup-apply-*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $NotBefore.AddSeconds(-5) } |
        Sort-Object LastWriteTime -Descending)) {
        try {
            $report = Get-Content -LiteralPath $reportFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($report.Status -eq 'Failed' -and -not [string]::IsNullOrWhiteSpace([string]$report.Error)) {
                return [pscustomobject]@{ Message = [string]$report.Error; Path = $reportFile.FullName }
            }
        }
        catch { }
    }
    return $null
}

function Invoke-PcSetupDesktopMachineSummary {
    param([Parameter(Mandatory)][hashtable]$Configuration)

    if (-not $Configuration.MachineAudit.Enabled -or -not $Configuration.MachineAudit.GenerateAfterReconciliation) { return }
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $machineSummaryPath -Config $Configuration._ConfigPath | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "A geracao do resumo da maquina falhou com codigo $LASTEXITCODE." }
}

try {
    [Console]::Title = "pc-setup - $operation e reconciliacao"
    Set-Location -LiteralPath $root

    Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.ExecutionLog.psm1') -Force
    $configuration = Import-PcSetupConfiguration -Path $Config
    if ($configuration.Runtime.ExecutionLogEnabled) {
        $executionLogDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'UserReportDirectory'
        $executionLog = New-PcSetupExecutionLog -Directory $executionLogDirectory -Operation $operation
        Write-PcSetupSessionEvent -Status Started -Message "$operation iniciada." -Data @{ Launcher = $LauncherName; WindowsAccount = $env:USERNAME; Profile = $configuration.ProfileName }
        Write-Host "[LOG] $($executionLog.Path)" -ForegroundColor DarkGray
    }
    $configHash = (Get-FileHash -LiteralPath $configuration._ConfigPath -Algorithm SHA256).Hash
    $projectHash = Get-PcSetupProjectFingerprint -Configuration $configuration
    $dailyUser = [string]$configuration.Accounts.DailyUser.Name
    $isDailyUser = $env:USERNAME -eq $dailyUser

    Write-Host "=== pc-setup: $($operation.ToLowerInvariant()) e reconciliacao ===" -ForegroundColor Cyan
    Write-Host 'O Windows e os ambientes WSL habilitados serao planejados, aplicados e validados.'
    if ($LauncherName -eq 'INSTALAR.cmd' -and $configuration.Debloat.Enabled) {
        Write-Host 'O debloat configurado faz parte do plano desta instalacao.'
    }
    Write-Host ''

    $environments = @()
    if ($configuration.Features.WSL) {
        $environments = @(Get-PcSetupWslEnvironments -Configuration $configuration |
            Where-Object { $_.Enabled -and $_.WindowsAccount -eq $env:USERNAME } |
            Sort-Object -Property @{ Expression = 'Default'; Descending = $true }, Name)
        if ($environments.Count -gt 0) {
            Write-Host 'Planos dos ambientes WSL:' -ForegroundColor Cyan
            foreach ($environment in $environments) {
                $currentStage = "PlanoWSL/$($environment.Name)"
                Write-PcSetupSessionEvent -Status Started -Message "Planejando o ambiente WSL $($environment.Name)." -Command 'wsl\bootstrap.ps1' -Arguments @('-Config', $Config, '-Environment', $environment.Name, '-Plan')
                & $wslBootstrapPath -Config $Config -Environment $environment.Name -Plan | Out-Null
                Write-PcSetupSessionEvent -Status Succeeded -Message "Plano WSL $($environment.Name) validado."
            }
            Write-Host ''
        }
    }

    $reconcileStateDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'UserStateDirectory'
    $reconcileStatePath = Join-Path $reconcileStateDirectory 'user-reconcile-state.json'
    $completedStatePath = Join-Path $reconcileStateDirectory 'user-reconcile-completed.json'
    $pendingUserPhase = $null
    $completedUserPhase = $null
    if ($isDailyUser -and (Test-Path -LiteralPath $reconcileStatePath -PathType Leaf)) {
        try { $pendingUserPhase = Get-Content -LiteralPath $reconcileStatePath -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { $pendingUserPhase = $null }
    }
    if ($isDailyUser -and (Test-Path -LiteralPath $completedStatePath -PathType Leaf)) {
        try { $completedUserPhase = Get-Content -LiteralPath $completedStatePath -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { $completedUserPhase = $null }
    }
    $completedApply = Get-CompletedWindowsApplyReport -Configuration $configuration
    $pendingMatches = $pendingUserPhase -and $completedApply -and
        $pendingUserPhase.SchemaVersion -eq 1 -and
        $pendingUserPhase.ConfigSha256 -eq $configHash -and
        $pendingUserPhase.ProjectSha256 -eq $projectHash -and
        $pendingUserPhase.WindowsApplyReport -eq $completedApply.Path
    $userPhaseAlreadyCompleted = $completedUserPhase -and $completedApply -and
        $completedUserPhase.SchemaVersion -eq 1 -and
        $completedUserPhase.ConfigSha256 -eq $configHash -and
        $completedUserPhase.ProjectSha256 -eq $projectHash -and
        $completedUserPhase.WindowsApplyReport -eq $completedApply.Path
    $resumeUserPhaseOnly = $isDailyUser -and $completedApply -and ($pendingMatches -or -not $userPhaseAlreadyCompleted)

    if ($resumeUserPhaseOnly) {
        $currentStage = 'Retomada'
        Write-PcSetupSessionEvent -Status Info -Message 'Windows ja concluido; retomando as fases da conta diaria.'
        Write-Host '[RETOMADA] O Windows ja foi aplicado e validado. Retomando pacotes, personalizacao e WSL da conta diaria.' -ForegroundColor Yellow
    }
    else {
        $currentStage = 'Windows'
        Write-PcSetupSessionEvent -Status Started -Message 'Iniciando planejamento, aplicacao e verificacao do Windows.' -Command 'powershell.exe' -Arguments @('-File', $startPath, '-Config', $configuration._ConfigPath, '-NoPause', '-LauncherName', $LauncherName)
        $windowsStartedAt = Get-Date
        & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $startPath -Config $configuration._ConfigPath -NoPause -LauncherName $LauncherName
        $windowsExitCode = $LASTEXITCODE
        if ($windowsExitCode -eq 2) {
            Write-PcSetupSessionEvent -Status Pending -Message "$operation cancelada antes da aplicacao." -Data @{ ExitCode = $windowsExitCode }
            Write-Host "$operation cancelada antes da aplicacao." -ForegroundColor Yellow
            exit 0
        }
        if ($windowsExitCode -eq 3) {
            Write-PcSetupSessionEvent -Status Pending -Message 'Reinicio do Windows necessario para continuar.' -Data @{ ExitCode = $windowsExitCode }
            Write-Host "Reinicie o Windows e execute $LauncherName novamente para continuar." -ForegroundColor Yellow
            exit 0
        }
        if ($windowsExitCode -ne 0) {
            $failure = Get-PcSetupWindowsFailureDiagnostic -Configuration $configuration -NotBefore $windowsStartedAt
            if ($failure) {
                throw "A reconciliacao do Windows falhou com codigo $windowsExitCode.`nDetalhe: $($failure.Message)`nDiagnostico: $($failure.Path)"
            }
            throw "A reconciliacao do Windows falhou com codigo $windowsExitCode e nao produziu um diagnostico legivel."
        }
        Write-PcSetupSessionEvent -Status Succeeded -Message 'Windows aplicado e validado.' -Data @{ ExitCode = $windowsExitCode }

        $completedApply = Get-CompletedWindowsApplyReport -Configuration $configuration
        if (-not $completedApply) { throw 'O Windows terminou sem um relatorio Apply concluido e validado para esta versao do projeto.' }
        if (-not $isDailyUser) {
            $currentStage = 'TrocaDeConta'
            Write-PcSetupSessionEvent -Status Pending -Message "Fase da maquina concluida; continuar na conta Windows $dailyUser."
            Write-Host ''
            Write-Host "[TROCA DE CONTA] A fase da maquina foi concluida. Entre na conta Windows $dailyUser e execute $LauncherName novamente." -ForegroundColor Yellow
            Write-Host "A conta esta habilitada e pertence ao grupo local Usuarios. Se o bloco ainda nao aparecer, encerre a sessao e use Outro usuario com .\$dailyUser."
            Write-Host 'Pacotes, personalizacao e WSL serao aplicados no perfil correto sem repetir a fase administrativa.'
            exit 0
        }
        $pendingState = [ordered]@{
            SchemaVersion      = 1
            CreatedAt          = (Get-Date).ToString('o')
            ConfigSha256       = $configHash
            ProjectSha256      = $projectHash
            WindowsApplyReport = $completedApply.Path
        }
        Write-PcSetupJson -InputObject $pendingState -Path $reconcileStatePath | Out-Null
    }

    Write-Host ''
    Write-Host '[USUARIO] Aplicando e validando configuracoes da conta diaria...' -ForegroundColor Cyan
    $includePersonalization = $false
    if ($configuration.Personalization.Enabled -and $LauncherName -eq 'INSTALAR.cmd') {
        $includePersonalization = [bool]$configuration.Personalization.ApplyOnInstall
    }
    elseif ($configuration.Personalization.Enabled -and $LauncherName -eq 'ATUALIZAR.cmd' -and $configuration.Personalization.PromptOnUpdate) {
        $personalizationAnswer = Read-Host 'Deseja reaplicar a personalizacao do Windows? Digite S para aplicar'
        $includePersonalization = $personalizationAnswer.Trim().ToUpperInvariant() -in @('S','SIM')
    }
    if ($includePersonalization) { Write-Host '[PERSONALIZACAO] Sera aplicada nesta execucao.' -ForegroundColor Yellow }
    else { Write-Host '[PERSONALIZACAO] Nao sera reaplicada nesta execucao.' -ForegroundColor DarkGray }
    $currentStage = 'PerfilUsuario'
    $userProfileArguments = @('-Config', $configuration._ConfigPath, '-WindowsApplyReport', $completedApply.Path)
    if ($includePersonalization) { $userProfileArguments += '-IncludePersonalization' }
    Write-PcSetupSessionEvent -Status Started -Message 'Aplicando pacotes e configuracoes da conta diaria.' -Command 'scripts\90-user-profile.ps1' -Arguments $userProfileArguments -Data @{ Personalization = $includePersonalization }
    & (Join-Path $root 'scripts\90-user-profile.ps1') -Config $configuration._ConfigPath -WindowsApplyReport $completedApply.Path -IncludePersonalization:$includePersonalization | Out-Host
    Write-PcSetupSessionEvent -Status Succeeded -Message 'Pacotes e configuracoes da conta diaria validados.' -Data @{ Personalization = $includePersonalization }

    if ($environments.Count -eq 0) {
        $knownGoodVersions = $null
        if ($configuration.Versions.CaptureKnownGood -and $configuration.Packages.Enabled) {
            $knownGoodVersions = & (Join-Path $root 'scripts\Save-PcSetupKnownGood.ps1') -Config $configuration._ConfigPath
        }
        $completedState = [ordered]@{
            SchemaVersion      = 1
            CompletedAt        = (Get-Date).ToString('o')
            ConfigSha256       = $configHash
            ProjectSha256      = $projectHash
            WindowsApplyReport = $completedApply.Path
            KnownGoodVersions  = if ($knownGoodVersions) { $knownGoodVersions.Path } else { $null }
        }
        Write-PcSetupJson -InputObject $completedState -Path $completedStatePath | Out-Null
        if (Test-Path -LiteralPath $reconcileStatePath -PathType Leaf) { Remove-Item -LiteralPath $reconcileStatePath -Force }
        Invoke-PcSetupDesktopMachineSummary -Configuration $configuration
        $currentStage = 'Conclusao'
        Write-PcSetupSessionEvent -Status Succeeded -Message "$operation e validacao concluidas sem ambientes WSL aplicaveis."
        Write-Host '[OK] Nenhum ambiente WSL habilitado para esta conta.' -ForegroundColor Green
        Write-Host "$($operation.ToUpperInvariant()) E VALIDACAO CONCLUIDAS." -ForegroundColor Green
        exit 0
    }

    foreach ($environment in $environments) {
        Write-Host ''
        Write-Host "[WSL] Reconciliando $($environment.Name)..." -ForegroundColor Cyan
        $currentStage = "WSL/$($environment.Name)"
        Write-PcSetupSessionEvent -Status Started -Message "Aplicando o ambiente WSL $($environment.Name)." -Command 'wsl\bootstrap.ps1' -Arguments @('-Config', $Config, '-Environment', $environment.Name, '-Apply')
        & $wslBootstrapPath -Config $Config -Environment $environment.Name -Apply | Out-Host
        Write-PcSetupSessionEvent -Status Info -Message "Aplicacao WSL $($environment.Name) concluida; iniciando verificacao." -Command 'wsl\verify.ps1' -Arguments @('-Config', $Config, '-Environment', $environment.Name)
        & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $wslVerifyPath -Config $Config -Environment $environment.Name | Out-Host
        $wslVerifyExitCode = $LASTEXITCODE
        if ($wslVerifyExitCode -ne 0) { throw "A verificacao WSL falhou para $($environment.Name) com codigo $wslVerifyExitCode." }
        Write-PcSetupSessionEvent -Status Succeeded -Message "Ambiente WSL $($environment.Name) aplicado e validado." -Data @{ ExitCode = $wslVerifyExitCode }
    }

    $knownGoodVersions = $null
    if ($configuration.Versions.CaptureKnownGood -and $configuration.Packages.Enabled) {
        $knownGoodVersions = & (Join-Path $root 'scripts\Save-PcSetupKnownGood.ps1') -Config $configuration._ConfigPath
    }

    $completedState = [ordered]@{
        SchemaVersion      = 1
        CompletedAt        = (Get-Date).ToString('o')
        ConfigSha256       = $configHash
        ProjectSha256      = $projectHash
        WindowsApplyReport = $completedApply.Path
        KnownGoodVersions  = if ($knownGoodVersions) { $knownGoodVersions.Path } else { $null }
    }
    Write-PcSetupJson -InputObject $completedState -Path $completedStatePath | Out-Null
    if (Test-Path -LiteralPath $reconcileStatePath -PathType Leaf) { Remove-Item -LiteralPath $reconcileStatePath -Force }
    Invoke-PcSetupDesktopMachineSummary -Configuration $configuration

    Write-Host ''
    $currentStage = 'Conclusao'
    Write-PcSetupSessionEvent -Status Succeeded -Message "$operation e validacao concluidas."
    Write-Host "$($operation.ToUpperInvariant()) E VALIDACAO CONCLUIDAS." -ForegroundColor Green
    exit 0
}
catch {
    $failure = $_
    Write-PcSetupSessionEvent -Status Failed -Message $failure.Exception.Message -Data @{ ErrorId = $failure.FullyQualifiedErrorId; Category = [string]$failure.CategoryInfo }
    Write-Host ''
    Write-Host "[ERRO] A $($operation.ToLowerInvariant()) foi interrompida com seguranca." -ForegroundColor Red
    Write-Host $failure.Exception.Message -ForegroundColor Red
    if ($null -ne $executionLog) { Write-Host "Log da sessao: $($executionLog.Path)" -ForegroundColor Yellow }
    exit 1
}
