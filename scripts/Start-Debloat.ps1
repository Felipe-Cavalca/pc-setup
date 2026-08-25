#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [switch]$ApplyConfirmed
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path $root 'config\machine.psd1' }
$configPath = [IO.Path]::GetFullPath($Config)
$debloatPath = Join-Path $PSScriptRoot '50-debloat-akita.ps1'
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Test-PcSetupAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-PcSetupExit {
    [void](Read-Host 'Pressione ENTER para fechar')
}

try {
    [Console]::Title = 'pc-setup - debloat'
    Set-Location -LiteralPath $root

    if ($ApplyConfirmed) {
        if (-not (Test-PcSetupAdministrator)) { throw 'A aplicacao confirmada do debloat exige permissao de Administrador.' }
        & $debloatPath -Config $configPath -Apply -ConfirmReviewed | Out-Host
        Write-Host ''
        Write-Host '[OK] Debloat concluido. Reinicie o Windows e execute VERIFICAR.cmd.' -ForegroundColor Green
        Wait-PcSetupExit
        exit 0
    }

    Write-Host '=== pc-setup: debloat independente ===' -ForegroundColor Cyan
    & $debloatPath -Config $configPath -Plan | Out-Host

    $answer = Read-Host 'Leu o plano e quer aplicar o debloat? Digite S para continuar'
    if ($answer.Trim().ToUpperInvariant() -notin @('S', 'SIM')) {
        Write-Host 'Debloat cancelado sem alterar o Windows.' -ForegroundColor Yellow
        Wait-PcSetupExit
        exit 0
    }

    if (Test-PcSetupAdministrator) {
        & $debloatPath -Config $configPath -Apply -ConfirmReviewed | Out-Host
        Write-Host ''
        Write-Host '[OK] Debloat concluido. Reinicie o Windows e execute VERIFICAR.cmd.' -ForegroundColor Green
        Wait-PcSetupExit
        exit 0
    }

    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Config `"$configPath`" -ApplyConfirmed"
    $process = Start-Process -FilePath $windowsPowerShell -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
}
catch {
    Write-Host ''
    Write-Host '[ERRO] O debloat foi interrompido com seguranca.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Wait-PcSetupExit
    exit 1
}
