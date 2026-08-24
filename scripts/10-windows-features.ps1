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
    WindowsSandbox         = 'Containers-DisposableClientVM'
    VirtualMachinePlatform = 'VirtualMachinePlatform'
    WSL                    = 'Microsoft-Windows-Subsystem-Linux'
}

$restartRequired = $false
$results = @()
$featureStates = [ordered]@{}
foreach ($key in $featureMap.Keys) {
    $featureName = $featureMap[$key]
    $requested = [bool]$configuration.Features[$key]
    if (-not $requested) {
        $featureStates[$key] = $null
        continue
    }

    try { $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop }
    catch { throw "O recurso opcional $featureName nao esta disponivel neste Windows. Detalhe: $($_.Exception.Message)" }
    $featureStates[$key] = $feature
}

$pendingVirtualization = @($featureMap.Keys | Where-Object {
    [bool]$configuration.Features[$_] -and $featureStates[$_].State -ne 'Enabled'
})
$virtualizationAssessment = Get-PcSetupVirtualizationAssessment -RequestedFeatures @()
if ($pendingVirtualization.Count -gt 0) {
    $hyperVState = if ($featureStates.HyperV) {
        [string]$featureStates.HyperV.State
    }
    else {
        [string](Get-WindowsOptionalFeature -Online -FeatureName $featureMap.HyperV -ErrorAction Stop).State
    }

    if ($hyperVState -eq 'Enabled') {
        $firmwareVirtualization = $true
        $secondLevelAddressTranslation = $true
        $vmMonitorModeExtensions = $true
        $dataExecutionPrevention = $true
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    }
    else {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
        $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        if ($processors.Count -eq 0) { throw 'O preflight nao conseguiu consultar os recursos do processador.' }

        $firmwareVirtualization = @($processors | Where-Object { $_.VirtualizationFirmwareEnabled -ne $true }).Count -eq 0
        $secondLevelAddressTranslation = @($processors | Where-Object { $_.SecondLevelAddressTranslationExtensions -ne $true }).Count -eq 0
        $vmMonitorModeExtensions = @($processors | Where-Object { $_.VMMonitorModeExtensions -ne $true }).Count -eq 0
        $dataExecutionPrevention = $operatingSystem.DataExecutionPrevention_Available -eq $true
    }

    $virtualizationAssessment = Get-PcSetupVirtualizationAssessment `
        -RequestedFeatures $pendingVirtualization `
        -FirmwareVirtualization $firmwareVirtualization `
        -SecondLevelAddressTranslation $secondLevelAddressTranslation `
        -VmMonitorModeExtensions $vmMonitorModeExtensions `
        -DataExecutionPrevention $dataExecutionPrevention

    $virtualizationAssessment | Add-Member -NotePropertyName ComputerModel -NotePropertyValue ([string]$computerSystem.Model)
    if (-not $virtualizationAssessment.Ready) {
        $hint = if ([string]$computerSystem.Model -match 'Virtual|VMware|VirtualBox|KVM|HVM') {
            'A maquina parece ser virtual. Desligue a VM e exponha as extensoes de virtualizacao no host; no Hyper-V, use Set-VMProcessor -VMName <nome> -ExposeVirtualizationExtensions $true.'
        }
        else {
            'Habilite Intel VT-x/AMD-V no firmware UEFI/BIOS e execute o plano novamente.'
        }
        throw "Preflight de virtualizacao falhou antes de qualquer alteracao. Ausente: $($virtualizationAssessment.Missing -join ', '). $hint"
    }
    Write-Host "[OK] Preflight de virtualizacao: $($pendingVirtualization -join ', ')."
}

foreach ($key in $featureMap.Keys) {
    $featureName = $featureMap[$key]
    $requested = [bool]$configuration.Features[$key]
    if (-not $requested) {
        $results += [pscustomobject]@{ Name = $featureName; Requested = $false; State = 'NotRequested'; Action = 'None' }
        continue
    }

    $feature = $featureStates[$key]
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
    Preflight       = $virtualizationAssessment
    Items           = $results
}
