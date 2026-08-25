#requires -Version 5.1
[CmdletBinding()]
param([string]$Config = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path $root 'config\machine.psd1' }
$configPath = [IO.Path]::GetFullPath($Config)
$personalizationPath = Join-Path $PSScriptRoot '80-personalization.ps1'
$machinePath = Join-Path $PSScriptRoot '82-personalization-machine.ps1'
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

try {
    [Console]::Title = 'pc-setup - Personalizacao do Windows'
    Set-Location -LiteralPath $root
    Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1') -Force
    $configuration = Import-PcSetupConfiguration -Path $configPath

    if ($env:USERNAME -ne [string]$configuration.Accounts.DailyUser.Name) {
        throw "Execute PERSONALIZAR.cmd na conta diaria $($configuration.Accounts.DailyUser.Name). Usuario atual: $env:USERNAME."
    }

    $reportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'ReportDirectory' -SystemRoot ([IO.Path]::GetPathRoot($env:SystemRoot))
    $completedReport = $null
    foreach ($file in @(Get-ChildItem -LiteralPath $reportDirectory -Filter 'pc-setup-apply-*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        try {
            $candidate = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($candidate.Status -eq 'Completed' -and $candidate.Profile -eq $configuration.ProfileName -and -not [string]::IsNullOrWhiteSpace([string]$candidate.Storage.DataRoot)) {
                $completedReport = [pscustomobject]@{ Path = $file.FullName; Report = $candidate }
                break
            }
        }
        catch { }
    }
    if (-not $completedReport) { throw 'Nenhuma instalacao concluida deste perfil foi encontrada. Execute INSTALAR.cmd antes da personalizacao manual.' }
    $dataRoot = [IO.Path]::GetFullPath([string]$completedReport.Report.Storage.DataRoot)

    Write-Host '=== pc-setup: personalizacao ===' -ForegroundColor Cyan
    Write-Host "Usuario: $env:USERNAME"
    Write-Host "Dados: $dataRoot"
    Write-Host ''
    & $machinePath -Config $configPath -Plan | Out-Host
    & $personalizationPath -Config $configPath -DataRoot $dataRoot -Plan | Out-Host

    Write-Host ''
    $answer = Read-Host 'Conferiu o plano e quer aplicar a personalizacao? Digite S para continuar'
    if ($answer.Trim().ToUpperInvariant() -notin @('S','SIM')) {
        Write-Host 'Personalizacao cancelada sem alteracoes.' -ForegroundColor Yellow
        exit 0
    }

    if (Test-PcSetupAdministrator) {
        & $machinePath -Config $configPath -CreateRestorePoint -Apply | Out-Host
    }
    else {
        $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$machinePath`" -Config `"$configPath`" -CreateRestorePoint -Apply"
        $process = Start-Process -FilePath $windowsPowerShell -ArgumentList $arguments -Verb RunAs -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "A fase administrativa da personalizacao falhou com codigo $($process.ExitCode)." }
    }

    & $personalizationPath -Config $configPath -DataRoot $dataRoot -Apply | Out-Host
    Write-Host ''
    Write-Host 'PERSONALIZACAO CONCLUIDA.' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ''
    Write-Host '[ERRO] A personalizacao foi interrompida com seguranca.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
