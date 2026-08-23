#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [switch]$Plan,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\machine.psd1' }
$coreModule = Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1'
$recoveryModule = Join-Path $PSScriptRoot 'lib\PcSetup.Recovery.psm1'
Import-Module $coreModule -Force
Import-Module $recoveryModule -Force

$mode = Get-PcSetupExecutionMode -Plan:$Plan -Apply:$Apply
$configuration = Import-PcSetupConfiguration -Path $Config
if ($mode -eq 'Apply') {
    Assert-PcSetupAdministrator
    $null = Enter-PcSetupProtectedScript -EntryPoint $MyInvocation.MyCommand.Name
}

$featureMap = [ordered]@{
    HyperV                 = 'Microsoft-Hyper-V-All'
    WindowsSandbox        = 'Containers-DisposableClientVM'
    VirtualMachinePlatform = 'VirtualMachinePlatform'
    WSL                    = 'Microsoft-Windows-Subsystem-Linux'
}

$restartRequired = $false
$results = @()
foreach ($key in $featureMap.Keys) {
    $featureName = $featureMap[$key]
    $requested = [bool]$configuration.Features[$key]
    if (-not $requested) {
        $results += [pscustomobject]@{ Name = $featureName; Requested = $false; State = 'NotRequested'; Action = 'None' }
        continue
    }

    $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop
    if ($feature.State -eq 'Enabled') {
        Write-Host "[OK] $featureName ja esta habilitado."
        $results += [pscustomobject]@{ Name = $featureName; Requested = $true; State = $feature.State; Action = 'None' }
        continue
    }

    if ($mode -eq 'Plan') {
        Write-Host "[PLANO] Habilitar $featureName (estado atual: $($feature.State))."
        $results += [pscustomobject]@{ Name = $featureName; Requested = $true; State = $feature.State; Action = 'Enable' }
        continue
    }

    Write-Host "[APLICAR] Habilitando $featureName..." -ForegroundColor Cyan
    $enabled = Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart -ErrorAction Stop
    $featureAfterApply = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop
    if ($featureAfterApply.State -notin @('Enabled', 'EnablePending')) {
        throw "$featureName permaneceu no estado $($featureAfterApply.State) depois da tentativa de habilitacao."
    }
    if ($enabled.RestartNeeded -or $featureAfterApply.State -eq 'EnablePending') { $restartRequired = $true }
    $results += [pscustomobject]@{ Name = $featureName; Requested = $true; State = [string]$featureAfterApply.State; Action = 'Enabled' }
}

[pscustomobject]@{
    Step            = 'WindowsFeatures'
    Mode            = $mode
    RestartRequired = $restartRequired
    Items           = $results
}
