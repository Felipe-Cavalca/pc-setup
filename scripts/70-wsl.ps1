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
Import-Module $coreModule -Force
Import-Module $recoveryModule -Force

$mode = Get-PcSetupExecutionMode -Plan:$Plan -Apply:$Apply
$configuration = Import-PcSetupConfiguration -Path $Config
if (-not $configuration.Features.WSL) {
    Write-Host '[IGNORADO] WSL desabilitado na configuracao.'
    return [pscustomobject]@{ Step = 'WSL'; Mode = $mode; Enabled = $false; Items = @() }
}

$actions = @()
if ($configuration.WSL.Update) { $actions += 'Update' }
if ([int]$configuration.WSL.DefaultVersion -gt 0) { $actions += "DefaultVersion=$($configuration.WSL.DefaultVersion)" }
if (-not [string]::IsNullOrWhiteSpace([string]$configuration.WSL.Distribution)) { $actions += "Install=$($configuration.WSL.Distribution)" }

if ($mode -eq 'Plan') {
    Write-Host "[PLANO] WSL: $($actions -join ', ')."
    return [pscustomobject]@{ Step = 'WSL'; Mode = $mode; Enabled = $true; Items = $actions }
}

Assert-PcSetupAdministrator
$null = Enter-PcSetupProtectedScript -EntryPoint $MyInvocation.MyCommand.Name
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe nao esta disponivel. Reinicie depois de habilitar os recursos do Windows e execute -Apply novamente.' }

if ($configuration.WSL.Update) {
    & wsl.exe --update | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "wsl --update falhou com codigo $LASTEXITCODE." }
}
if ([int]$configuration.WSL.DefaultVersion -gt 0) {
    & wsl.exe --set-default-version ([int]$configuration.WSL.DefaultVersion) | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "wsl --set-default-version falhou com codigo $LASTEXITCODE." }
}
if (-not [string]::IsNullOrWhiteSpace([string]$configuration.WSL.Distribution)) {
    & wsl.exe --install --distribution ([string]$configuration.WSL.Distribution) --no-launch | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Instalacao da distribuicao WSL falhou com codigo $LASTEXITCODE." }
}

Write-Host '[OK] Configuracao do WSL concluida. Distribuicoes e ambientes continuam separados por usuario.' -ForegroundColor Green
[pscustomobject]@{ Step = 'WSL'; Mode = $mode; Enabled = $true; Items = $actions }
