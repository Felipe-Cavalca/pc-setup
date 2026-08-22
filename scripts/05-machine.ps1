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
$desiredName = [string]$configuration.Machine.ComputerName
$currentName = [string]$env:COMPUTERNAME
if ([string]::IsNullOrWhiteSpace($desiredName) -or $desiredName -eq $currentName) {
    Write-Host "[OK] Nome do computador preservado: $currentName."
    return [pscustomobject]@{ Step = 'Machine'; Mode = $mode; CurrentName = $currentName; DesiredName = $desiredName; Action = 'None'; RestartRequired = $false }
}

if ($mode -eq 'Plan') {
    Write-Host "[PLANO] Renomear o computador de $currentName para $desiredName."
    return [pscustomobject]@{ Step = 'Machine'; Mode = $mode; CurrentName = $currentName; DesiredName = $desiredName; Action = 'Rename'; RestartRequired = $true }
}

Assert-PcSetupAdministrator
$null = Enter-PcSetupProtectedScript -EntryPoint $MyInvocation.MyCommand.Name
Rename-Computer -NewName $desiredName -Force -ErrorAction Stop
Write-Host "[APLICADO] O computador sera renomeado para $desiredName depois do reinicio." -ForegroundColor Green
[pscustomobject]@{ Step = 'Machine'; Mode = $mode; CurrentName = $currentName; DesiredName = $desiredName; Action = 'Renamed'; RestartRequired = $true }
