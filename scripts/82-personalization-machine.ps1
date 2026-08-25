#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [string]$WindowsApplyReport = '',
    [switch]$CreateRestorePoint,
    [switch]$Plan,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\machine.psd1' }
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Recovery.psm1') -Force

$mode = Get-PcSetupExecutionMode -Plan:$Plan -Apply:$Apply
$configuration = Import-PcSetupConfiguration -Path $Config
$personalization = $configuration.Personalization
$allFolders = @('Documents','Downloads','FileExplorer','HomeGroup','Music','Network','PersonalFolder','Pictures','Settings','Videos')

if (-not $personalization.Enabled) {
    Write-Host '[IGNORADO] Personalizacao de maquina desabilitada.'
    return [pscustomobject]@{ Step = 'PersonalizationMachine'; Mode = $mode; Enabled = $false; Action = 'None' }
}

if ($mode -eq 'Plan') {
    Write-Host "[PLANO] Mostrar no menu Iniciar somente: $(@($personalization.StartPowerMenuFolders) -join ', ')."
    return [pscustomobject]@{
        Step = 'PersonalizationMachine'; Mode = $mode; Enabled = $true
        StartPowerMenuFolders = @($personalization.StartPowerMenuFolders); Action = 'Plan'
    }
}

Assert-PcSetupAdministrator
$sessionStarted = $false
try {
    if ($CreateRestorePoint) {
        $null = Start-PcSetupChangeSession -EntryPoint 'PERSONALIZAR.cmd'
        $sessionStarted = $true
    }
    else {
        if ([string]::IsNullOrWhiteSpace($WindowsApplyReport)) { throw 'A personalizacao automatica exige o relatorio protegido da fase Windows.' }
        $null = Assert-PcSetupCompletedApplyReport -Configuration $configuration -Path $WindowsApplyReport
    }

    $policyPath = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start'
    if (-not (Test-Path -LiteralPath $policyPath)) { New-Item -Path $policyPath -Force | Out-Null }
    foreach ($folder in $allFolders) {
        $value = if (@($personalization.StartPowerMenuFolders) -contains $folder) { 1 } else { 0 }
        New-ItemProperty -LiteralPath $policyPath -Name "AllowPinnedFolder$folder" -PropertyType DWord -Value $value -Force | Out-Null
    }

    foreach ($folder in $allFolders) {
        $expected = if (@($personalization.StartPowerMenuFolders) -contains $folder) { 1 } else { 0 }
        $actual = [int](Get-ItemPropertyValue -LiteralPath $policyPath -Name "AllowPinnedFolder$folder" -ErrorAction Stop)
        if ($actual -ne $expected) { throw "A politica do atalho $folder no menu Iniciar nao foi confirmada." }
    }

    $result = [ordered]@{
        Step                  = 'PersonalizationMachine'
        Mode                  = $mode
        Enabled               = $true
        StartPowerMenuFolders = @($personalization.StartPowerMenuFolders)
        CompletedAt           = (Get-Date).ToString('o')
        Action                = 'Completed'
    }
    $reportPath = Join-Path (Get-PcSetupRuntimePath -Configuration $configuration -Key 'ReportDirectory' -SystemRoot ([IO.Path]::GetPathRoot($env:SystemRoot))) ('personalization-machine-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    Write-PcSetupJson -InputObject $result -Path $reportPath | Out-Null
    Write-Host "[RELATORIO] $reportPath" -ForegroundColor Green
    [pscustomobject]$result
}
finally {
    if ($sessionStarted) { Stop-PcSetupChangeSession }
}
