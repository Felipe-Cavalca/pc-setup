#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [Parameter(Mandatory)][string]$WindowsApplyReport,
    [switch]$IncludePersonalization
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\machine.psd1' }
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1') -Force
$configuration = Import-PcSetupConfiguration -Path $Config
if ($env:USERNAME -ne [string]$configuration.Accounts.DailyUser.Name) {
    throw "A fase de usuario deve ser executada na conta diaria $($configuration.Accounts.DailyUser.Name). Usuario atual: $env:USERNAME."
}
$applyReport = Assert-PcSetupCompletedApplyReport -Configuration $configuration -Path $WindowsApplyReport

$steps = @()
$steps += & (Join-Path $PSScriptRoot '60-packages.ps1') -Config $configuration._ConfigPath -WindowsApplyReport $WindowsApplyReport -Apply
if ($IncludePersonalization -and $configuration.Personalization.Enabled) {
    $machinePersonalizationPath = Join-Path $PSScriptRoot '82-personalization-machine.ps1'
    if (Test-PcSetupAdministrator) {
        $steps += & $machinePersonalizationPath -Config $configuration._ConfigPath -WindowsApplyReport $WindowsApplyReport -Apply
    }
    else {
        $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$machinePersonalizationPath`" -Config `"$($configuration._ConfigPath)`" -WindowsApplyReport `"$WindowsApplyReport`" -Apply"
        $process = Start-Process -FilePath $windowsPowerShell -ArgumentList $arguments -Verb RunAs -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "A fase administrativa da personalizacao falhou com codigo $($process.ExitCode)." }
        $steps += [pscustomobject]@{ Step = 'PersonalizationMachine'; Mode = 'Apply'; Enabled = $true; Action = 'CompletedInElevatedProcess' }
    }
    $steps += & (Join-Path $PSScriptRoot '80-personalization.ps1') -Config $configuration._ConfigPath -WindowsApplyReport $WindowsApplyReport -Apply
}

$report = [ordered]@{
    GeneratedAt        = (Get-Date).ToString('o')
    Status             = 'Completed'
    User               = $env:USERNAME
    Profile            = $configuration.ProfileName
    ConfigSha256       = $applyReport.ConfigSha256
    ProjectSha256      = $applyReport.ProjectSha256
    WindowsApplyReport = $WindowsApplyReport
    Personalization    = [bool]$IncludePersonalization
    Steps              = $steps
}
$reportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'UserReportDirectory'
$reportPath = Join-Path $reportDirectory ('user-profile-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
Write-PcSetupJson -InputObject $report -Path $reportPath | Out-Null
Write-Host "[RELATORIO] Fase da conta diaria: $reportPath" -ForegroundColor Green
[pscustomobject]$report
