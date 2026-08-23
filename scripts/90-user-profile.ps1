#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [Parameter(Mandatory)][string]$WindowsApplyReport
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
$steps += & (Join-Path $PSScriptRoot '80-personalization.ps1') -Config $configuration._ConfigPath -WindowsApplyReport $WindowsApplyReport -Apply

$report = [ordered]@{
    GeneratedAt        = (Get-Date).ToString('o')
    Status             = 'Completed'
    User               = $env:USERNAME
    Profile            = $configuration.ProfileName
    ConfigSha256       = $applyReport.ConfigSha256
    ProjectSha256      = $applyReport.ProjectSha256
    WindowsApplyReport = $WindowsApplyReport
    Steps              = $steps
}
$reportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'UserReportDirectory'
$reportPath = Join-Path $reportDirectory ('user-profile-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
Write-PcSetupJson -InputObject $report -Path $reportPath | Out-Null
Write-Host "[RELATORIO] Fase da conta diaria: $reportPath" -ForegroundColor Green
[pscustomobject]$report
