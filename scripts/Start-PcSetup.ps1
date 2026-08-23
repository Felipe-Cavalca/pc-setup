#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [switch]$NoPause,
    [ValidateSet('INSTALAR.cmd','ATUALIZAR.cmd')]
    [string]$LauncherName = 'INSTALAR.cmd'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path $root 'config\machine.psd1' }
$configPath = [IO.Path]::GetFullPath($Config)
$bootstrapPath = Join-Path $root 'bootstrap.ps1'
$verifyPath = Join-Path $root 'verify.ps1'
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$operation = if ($LauncherName -eq 'INSTALAR.cmd') { 'Instalacao' } else { 'Atualizacao' }

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-PcSetupExit {
    if ($NoPause) { return }
    [void](Read-Host 'Pressione ENTER para fechar')
}

function Write-PcSetupFailureDiagnostic {
    param(
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [Parameter(Mandatory)][string]$Path
    )

    try {
        $directory = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $diagnostic = [ordered]@{
            SchemaVersion    = 1
            OccurredAt       = (Get-Date).ToString('o')
            Operation        = $operation
            LauncherName     = $LauncherName
            Message          = $ErrorRecord.Exception.Message
            FullyQualifiedId = $ErrorRecord.FullyQualifiedErrorId
            Category         = [string]$ErrorRecord.CategoryInfo
            Position         = $ErrorRecord.InvocationInfo.PositionMessage
            ScriptStackTrace = $ErrorRecord.ScriptStackTrace
        }
        $diagnostic | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
        return $true
    }
    catch {
        Write-Warning "Nao foi possivel gravar o diagnostico da falha: $($_.Exception.Message)"
        return $false
    }
}

if (-not (Test-Administrator)) {
    try {
        $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Config `"$configPath`" -LauncherName $LauncherName"
        if ($NoPause) { $arguments += ' -NoPause' }
        $process = Start-Process -FilePath $windowsPowerShell -ArgumentList $arguments -Verb RunAs -Wait -PassThru
        exit $process.ExitCode
    }
    catch {
        Write-Host "Nao foi possivel obter permissao de Administrador: $($_.Exception.Message)" -ForegroundColor Red
        Wait-PcSetupExit
        exit 1
    }
}

$lastErrorPath = Join-Path $env:ProgramData 'pc-setup\last-error.json'
try {
    [Console]::Title = "pc-setup - $operation do Windows"
    Set-Location -LiteralPath $root

    $coreModule = Join-Path $root 'scripts\lib\PcSetup.Core.psm1'
    Import-Module $coreModule -Force
    $configuration = Import-PcSetupConfiguration -Path $configPath
    $systemRoot = [IO.Path]::GetPathRoot($env:SystemRoot)
    $stateDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'StateDirectory' -SystemRoot $systemRoot
    $reportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'ReportDirectory' -SystemRoot $systemRoot
    $lastErrorPath = Join-Path $stateDirectory 'last-error.json'
    if (Test-Path -LiteralPath $lastErrorPath -PathType Leaf) { Remove-Item -LiteralPath $lastErrorPath -Force -ErrorAction SilentlyContinue }
    $applyStatePath = Join-Path $stateDirectory 'apply-state.json'

    Clear-Host
    Write-Host "=== pc-setup: $($operation.ToLowerInvariant()) assistida ===" -ForegroundColor Cyan
    Write-Host "Perfil: $($configuration.ProfileName)"
    Write-Host ''

    if (Test-Path -LiteralPath $applyStatePath -PathType Leaf) {
        $state = Get-Content -Raw -LiteralPath $applyStatePath | ConvertFrom-Json
        Write-Host "Retomando a instalacao na etapa: $($state.Stage)." -ForegroundColor Yellow
        & $bootstrapPath -Config $configPath -Apply
    }
    else {
        Write-Host 'Primeiro sera mostrado o plano. Nenhuma configuracao do Windows sera alterada nessa etapa.' -ForegroundColor Gray
        & $bootstrapPath -Config $configPath -Plan

        Write-Host ''
        $answer = Read-Host "Conferiu o plano e quer iniciar a $($operation.ToLowerInvariant())? Digite S para continuar"
        if ($answer.Trim().ToUpperInvariant() -notin @('S', 'SIM')) {
            Write-Host "$operation cancelada. O plano foi mantido para consulta." -ForegroundColor Yellow
            Wait-PcSetupExit
            if ($NoPause) { exit 2 }
            exit 0
        }

        & $bootstrapPath -Config $configPath -Apply
    }

    if (Test-Path -LiteralPath $applyStatePath -PathType Leaf) {
        $state = Get-Content -Raw -LiteralPath $applyStatePath | ConvertFrom-Json
        if ($state.Stage -eq 'RestartRequired') {
            Write-Host ''
            Write-Host 'REINICIO NECESSARIO' -ForegroundColor Yellow
            Write-Host "Reinicie o Windows e clique em $LauncherName novamente. A aplicacao continuara do ponto correto."
        }
        else {
            Write-Host "A aplicacao ficou pendente na etapa $($state.Stage). Clique em $LauncherName novamente para tentar continuar." -ForegroundColor Yellow
        }
        Wait-PcSetupExit
        if ($NoPause) { exit 3 }
        exit 0
    }

    Write-Host ''
    Write-Host 'Executando a verificacao final...' -ForegroundColor Cyan
    $verificationReportPath = Join-Path $reportDirectory ('verify-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $verifyPath -Config $configPath -ReportPath $verificationReportPath
    $verificationExitCode = $LASTEXITCODE
    if ($verificationExitCode -eq 0) {
        Write-Host ''
        Write-Host "$($operation.ToUpperInvariant()) E VALIDACAO CONCLUIDAS." -ForegroundColor Green
        Wait-PcSetupExit
        exit 0
    }

    $verificationMessage = "A validacao final encontrou falhas. Codigo: $verificationExitCode."
    try {
        $verificationReport = Get-Content -LiteralPath $verificationReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $failedChecks = @($verificationReport.Checks | Where-Object Status -eq 'FAIL')
        if ($failedChecks.Count -gt 0) {
            $failedDetails = @($failedChecks | ForEach-Object { "$($_.Name): $($_.Detail)" })
            $verificationMessage = "A validacao final encontrou $($failedChecks.Count) falha(s):`n- $($failedDetails -join "`n- ")"
        }
    }
    catch {
        $verificationMessage += " O relatorio nao pode ser lido: $($_.Exception.Message)"
    }
    throw "$verificationMessage`nRelatorio: $verificationReportPath"
}
catch {
    $failure = $_
    $diagnosticWritten = Write-PcSetupFailureDiagnostic -ErrorRecord $failure -Path $lastErrorPath
    Write-Host ''
    Write-Host 'O pc-setup foi interrompido com seguranca.' -ForegroundColor Red
    Write-Host $failure.Exception.Message -ForegroundColor Red
    if ($diagnosticWritten) { Write-Host "Diagnostico: $lastErrorPath" -ForegroundColor Yellow }
    Write-Host "Corrija o item informado e clique em $LauncherName novamente." -ForegroundColor Yellow
    Wait-PcSetupExit
    exit 1
}
