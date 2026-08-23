#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\machine.psd1'),
    [string]$Environment = '',
    [string]$ReportPath = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'PcSetup.Wsl.psm1') -Force

$configuration = Import-PcSetupConfiguration -Path $Config
$target = Resolve-PcSetupWslTarget -Configuration $configuration -EnvironmentName $Environment
$environmentDefinition = $target.Environment
$profile = $target.Profile
if ($env:USERNAME -ne $environmentDefinition.WindowsAccount) {
    throw "O ambiente $($environmentDefinition.Name) deve ser verificado durante uma sessao da conta Windows $($environmentDefinition.WindowsAccount). Usuario atual: $env:USERNAME."
}
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe nao encontrado.' }

$distribution = [string]$environmentDefinition.Distribution
$installed = @(Get-PcSetupWslDistributionNames)
if ($installed -notcontains $distribution) { throw "Distribuicao WSL ausente para $env:USERNAME: $distribution" }
$actualVersion = Get-PcSetupWslDistributionVersion -Distribution $distribution
$expectedVersion = [int]$configuration.WSL.DefaultVersion
if ($actualVersion -ne $expectedVersion) { throw "Versao WSL incorreta para ${distribution}: esperada $expectedVersion; encontrada $actualVersion." }
$defaultUser = Get-PcSetupWslDefaultUser -Distribution $distribution
$expectedDefaultUser = Get-PcSetupExpectedWslDefaultUser -Configuration $configuration -Environment $environmentDefinition
if ($defaultUser -ne $expectedDefaultUser) { throw "Usuario padrao incorreto em ${distribution}: esperado $expectedDefaultUser; encontrado $defaultUser." }

$verifyLinuxPath = ConvertTo-PcSetupWslPath -Distribution $distribution -WindowsPath (Join-Path $PSScriptRoot 'linux\verify.sh')
$verifyResult = Invoke-PcSetupWslLinuxScript -Distribution $distribution -ScriptPath $verifyLinuxPath -Environment $environmentDefinition -Profile $profile
$status = if ($verifyResult.ExitCode -eq 0) { 'PASS' } else { 'FAIL' }
$installedState = Get-PcSetupWslInstalledState -Distribution $distribution -ProfileName $environmentDefinition.Name
$report = [ordered]@{
    GeneratedAt    = (Get-Date).ToString('o')
    Environment    = $environmentDefinition.Name
    WindowsAccount = $environmentDefinition.WindowsAccount
    Distribution   = $distribution
    WslVersion     = $actualVersion
    LinuxUser      = $profile.LinuxUser
    DefaultUser    = $defaultUser
    ExpectedDefaultUser = $expectedDefaultUser
    ProjectRoot    = $profile.ProjectRoot
    Packages       = @($profile.Packages)
    AiJail         = if ($profile.ContainsKey('AiJail')) { $profile.AiJail } else { $null }
    Harness        = if ($profile.ContainsKey('Harness')) { $profile.Harness } else { $null }
    InstalledState = $installedState
    Status         = $status
    Output         = @($verifyResult.Output)
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $reportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'UserReportDirectory'
    $ReportPath = Join-Path $reportDirectory ('wsl-verify-' + $environmentDefinition.Name.ToLowerInvariant() + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
}
Write-PcSetupJson -InputObject $report -Path $ReportPath | Out-Null
Write-Host "[RELATORIO] $ReportPath"
if ($verifyResult.ExitCode -ne 0) { exit 1 }
$report
