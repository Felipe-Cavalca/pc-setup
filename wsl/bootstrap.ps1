#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\machine.psd1'),
    [string]$Environment = '',
    [switch]$Plan,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'PcSetup.Wsl.psm1') -Force

$mode = Get-PcSetupExecutionMode -Plan:$Plan -Apply:$Apply
$configuration = Import-PcSetupConfiguration -Path $Config
$target = Resolve-PcSetupWslTarget -Configuration $configuration -EnvironmentName $Environment
$environmentDefinition = $target.Environment
$profile = $target.Profile

$planItems = @(
    "WindowsAccount=$($environmentDefinition.WindowsAccount)",
    "Distribution=$($environmentDefinition.Distribution)",
    "LinuxUser=$($profile.LinuxUser)",
    "ProjectRoot=$($profile.ProjectRoot)",
    "Packages=$(@($profile.Packages).Count)",
    "DefaultUser=$([bool]$profile.SetAsDefaultUser)",
    "AiJail=$([bool]($profile.ContainsKey('AiJail') -and $profile.AiJail.Enabled))"
)
if ($profile.ContainsKey('Harness') -and $profile.Harness.Enabled) {
    $planItems += "Harness=$($profile.Harness.Package)@$($profile.Harness.Version) ($($profile.Harness.Command))"
}
if ($mode -eq 'Plan') {
    Write-Host "[PLANO] WSL $($environmentDefinition.Name): $($planItems -join ', ')."
    return [pscustomobject]@{ Step = 'WslEnvironment'; Mode = $mode; Environment = $environmentDefinition.Name; Items = $planItems }
}

if ($env:USERNAME -ne $environmentDefinition.WindowsAccount) {
    throw "O ambiente $($environmentDefinition.Name) deve ser aplicado durante uma sessao da conta Windows $($environmentDefinition.WindowsAccount). Usuario atual: $env:USERNAME."
}
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe nao encontrado. Execute primeiro o bootstrap principal e reinicie o Windows.' }

$distribution = [string]$environmentDefinition.Distribution
$installed = @(Get-PcSetupWslDistributionNames)
$installedNow = $false
if ($installed -notcontains $distribution) {
    Write-Host "[WSL] Instalando $distribution para $env:USERNAME..." -ForegroundColor Cyan
    & wsl.exe --install --distribution $distribution --no-launch | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "wsl --install falhou com codigo $LASTEXITCODE." }
    $installedNow = $true
}
else {
    Write-Host "[OK] $distribution ja esta registrada para $env:USERNAME."
}

$bootstrapLinuxPath = ConvertTo-PcSetupWslPath -Distribution $distribution -WindowsPath (Join-Path $PSScriptRoot 'linux\bootstrap.sh')
$verifyLinuxPath = ConvertTo-PcSetupWslPath -Distribution $distribution -WindowsPath (Join-Path $PSScriptRoot 'linux\verify.sh')
$bootstrapResult = Invoke-PcSetupWslLinuxScript -Distribution $distribution -ScriptPath $bootstrapLinuxPath -Environment $environmentDefinition -Profile $profile
if ($bootstrapResult.ExitCode -ne 0) { throw "Bootstrap Linux falhou com codigo $($bootstrapResult.ExitCode)." }
& wsl.exe --terminate $distribution | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Nao foi possivel reiniciar $distribution para aplicar /etc/wsl.conf." }
$defaultUser = Get-PcSetupWslDefaultUser -Distribution $distribution
$expectedDefaultUser = Get-PcSetupExpectedWslDefaultUser -Configuration $configuration -Environment $environmentDefinition
if ($defaultUser -ne $expectedDefaultUser) { throw "Usuario padrao incorreto em ${distribution}: esperado $expectedDefaultUser; encontrado $defaultUser." }
$verifyResult = Invoke-PcSetupWslLinuxScript -Distribution $distribution -ScriptPath $verifyLinuxPath -Environment $environmentDefinition -Profile $profile
if ($verifyResult.ExitCode -ne 0) { throw "Verificacao Linux falhou com codigo $($verifyResult.ExitCode)." }
$installedState = Get-PcSetupWslInstalledState -Distribution $distribution -ProfileName $environmentDefinition.Name

$report = [ordered]@{
    GeneratedAt    = (Get-Date).ToString('o')
    Environment    = $environmentDefinition.Name
    WindowsAccount = $environmentDefinition.WindowsAccount
    Distribution   = $distribution
    WslVersion     = Get-PcSetupWslDistributionVersion -Distribution $distribution
    LinuxUser      = $profile.LinuxUser
    DefaultUser    = $defaultUser
    ExpectedDefaultUser = $expectedDefaultUser
    ProjectRoot    = $profile.ProjectRoot
    Packages       = @($profile.Packages)
    AiJail         = if ($profile.ContainsKey('AiJail')) { $profile.AiJail } else { $null }
    Harness        = if ($profile.ContainsKey('Harness')) { $profile.Harness } else { $null }
    InstalledState = $installedState
    InstalledNow   = $installedNow
    Status         = 'Completed'
}
$reportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'UserReportDirectory'
$reportPath = Join-Path $reportDirectory ('wsl-bootstrap-' + $environmentDefinition.Name.ToLowerInvariant() + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
Write-PcSetupJson -InputObject $report -Path $reportPath | Out-Null
Write-Host "[RELATORIO] $reportPath" -ForegroundColor Green
$report
