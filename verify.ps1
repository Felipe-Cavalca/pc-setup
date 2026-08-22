#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = (Join-Path $PSScriptRoot 'config\machine.psd1'),
    [string]$ReportPath = ''
)

$ErrorActionPreference = 'Continue'
$coreModule = Join-Path $PSScriptRoot 'scripts\lib\PcSetup.Core.psm1'
Import-Module $coreModule -Force
$configuration = Import-PcSetupConfiguration -Path $Config
Assert-PcSetupAdministrator

$checks = @()
$information = [ordered]@{}
function Add-Check {
    param(
        [Parameter(Mandatory)][ValidateSet('PASS','WARN','FAIL','INFO')][string]$Status,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Detail
    )
    $color = switch ($Status) { 'PASS' { 'Green' } 'WARN' { 'Yellow' } 'FAIL' { 'Red' } default { 'Gray' } }
    Write-Host ("[{0}] {1}: {2}" -f $Status, $Name, $Detail) -ForegroundColor $color
    $script:checks += [pscustomobject]@{ Status = $Status; Name = $Name; Detail = $Detail }
}

Write-Host '=== pc-setup verify ===' -ForegroundColor Cyan

try {
    $computerInfo = Get-ComputerInfo -Property WindowsProductName -ErrorAction Stop
    $editionOk = if ($configuration.Windows.Edition -eq 'Professional') { $computerInfo.WindowsProductName -match ' Pro' } else { $computerInfo.WindowsProductName -match [regex]::Escape([string]$configuration.Windows.Edition) }
    Add-Check -Status $(if ($editionOk) { 'PASS' } else { 'FAIL' }) -Name 'Edicao do Windows' -Detail ([string]$computerInfo.WindowsProductName)

    $windows = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $build = [int]$windows.CurrentBuildNumber
    Add-Check -Status $(if ($windows.DisplayVersion -eq $configuration.Windows.TargetVersion) { 'PASS' } else { 'WARN' }) -Name 'Versao do Windows' -Detail "esperada $($configuration.Windows.TargetVersion); encontrada $($windows.DisplayVersion)"
    Add-Check -Status $(if ($build -ge [int]$configuration.Windows.MinimumBuild) { 'PASS' } else { 'FAIL' }) -Name 'Build do Windows' -Detail "minima $($configuration.Windows.MinimumBuild); encontrada $build"
}
catch { Add-Check -Status 'FAIL' -Name 'Windows' -Detail $_.Exception.Message }

try {
    $licensing = Get-CimInstance SoftwareLicensingProduct -Filter "Name like 'Windows%' and PartialProductKey is not null" -ErrorAction Stop | Where-Object LicenseStatus -eq 1 | Select-Object -First 1
    Add-Check -Status $(if ($licensing) { 'PASS' } else { 'WARN' }) -Name 'Ativacao' -Detail $(if ($licensing) { 'Windows ativado' } else { 'licenca ativa nao encontrada' })
}
catch { Add-Check -Status 'WARN' -Name 'Ativacao' -Detail $_.Exception.Message }

$storage = $null
$paths = $null
try {
    $storage = Resolve-PcSetupStorage -Configuration $configuration
    $paths = Get-PcSetupConfiguredPaths -Configuration $configuration -Storage $storage
    Add-Check -Status 'PASS' -Name 'Armazenamento' -Detail "Windows=$($storage.SystemRoot); dados=$($storage.DataRoot); modo=$($storage.DataMode)"
}
catch { Add-Check -Status 'FAIL' -Name 'Armazenamento' -Detail $_.Exception.Message }

$featureMap = [ordered]@{
    HyperV = 'Microsoft-Hyper-V-All'
    WindowsSandbox = 'Containers-DisposableClientVM'
    VirtualMachinePlatform = 'VirtualMachinePlatform'
    WSL = 'Microsoft-Windows-Subsystem-Linux'
}
foreach ($key in $featureMap.Keys) {
    if (-not $configuration.Features[$key]) { continue }
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureMap[$key] -ErrorAction Stop
        Add-Check -Status $(if ($feature.State -eq 'Enabled') { 'PASS' } else { 'FAIL' }) -Name $featureMap[$key] -Detail ([string]$feature.State)
    }
    catch { Add-Check -Status 'FAIL' -Name $featureMap[$key] -Detail $_.Exception.Message }
}

try {
    $adminGroup = ([Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
    $adminMembers = @(Get-LocalGroupMember -Group $adminGroup -ErrorAction Stop)
    foreach ($account in @(Get-PcSetupAccounts -Configuration $configuration | Where-Object Enabled)) {
        $user = Get-LocalUser -Name $account.Name -ErrorAction SilentlyContinue
        if (-not $user) {
            Add-Check -Status 'FAIL' -Name "Usuario $($account.Name)" -Detail 'conta ausente'
            continue
        }
        Add-Check -Status 'PASS' -Name "Usuario $($account.Name)" -Detail 'conta presente'
        $isAdmin = $null -ne ($adminMembers | Where-Object { $_.Name -match "\\$([regex]::Escape($account.Name))$" } | Select-Object -First 1)
        if ($account.Role -eq 'Administrator') {
            Add-Check -Status $(if ($isAdmin) { 'PASS' } else { 'FAIL' }) -Name "Papel $($account.Name)" -Detail $(if ($isAdmin) { 'administrador' } else { 'nao e administrador' })
        }
        elseif ($isAdmin -and $account.Key -eq 'DailyUser' -and -not $configuration.Security.DemoteDailyUserAutomatically) {
            Add-Check -Status 'WARN' -Name "Papel $($account.Name)" -Detail "ainda administrador; teste $($configuration.Accounts.RecoveryAdmin.Name) e rebaixe manualmente"
        }
        else {
            Add-Check -Status $(if (-not $isAdmin) { 'PASS' } else { 'FAIL' }) -Name "Papel $($account.Name)" -Detail $(if ($isAdmin) { 'administrador indevido' } else { 'usuario padrao' })
        }
    }
}
catch { Add-Check -Status 'FAIL' -Name 'Usuarios locais' -Detail $_.Exception.Message }

if ($paths) {
    foreach ($key in @($paths.Keys | Sort-Object)) {
        Add-Check -Status $(if (Test-Path -LiteralPath $paths[$key] -PathType Container) { 'PASS' } else { 'FAIL' }) -Name "Diretorio $key" -Detail $paths[$key]
    }

    $aclExpectations = @(
        @{ Key = 'Development'; Users = @($configuration.Accounts.DailyUser.Name, $configuration.Accounts.Codex.Name) },
        @{ Key = 'PersonalData'; Users = @($configuration.Accounts.DailyUser.Name) }
    )
    if (-not $configuration.Accounts.Codex.Enabled) { $aclExpectations[0].Users = @($configuration.Accounts.DailyUser.Name) }
    if ($configuration.Accounts.Codex.Enabled) { $aclExpectations += @{ Key = 'AgentData'; Users = @($configuration.Accounts.Codex.Name) } }
    foreach ($expectation in $aclExpectations) {
        $path = $paths[$expectation.Key]
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
        try {
            $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
            Add-Check -Status $(if ($acl.AreAccessRulesProtected) { 'PASS' } else { 'FAIL' }) -Name "Heranca ACL $($expectation.Key)" -Detail $(if ($acl.AreAccessRulesProtected) { 'protegida' } else { 'ainda herdada' })
            $allowRules = @($acl.Access | Where-Object AccessControlType -eq 'Allow')
            $identities = @($allowRules | ForEach-Object { $_.IdentityReference.Value })
            $systemName = ([Security.Principal.SecurityIdentifier]'S-1-5-18').Translate([Security.Principal.NTAccount]).Value
            $administratorsName = ([Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value
            foreach ($builtIn in @($systemName, $administratorsName)) {
                $fullControl = $null -ne ($allowRules | Where-Object { $_.IdentityReference.Value -eq $builtIn -and ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl } | Select-Object -First 1)
                Add-Check -Status $(if ($fullControl) { 'PASS' } else { 'FAIL' }) -Name "ACL $($expectation.Key)/$builtIn" -Detail $(if ($fullControl) { 'controle total' } else { 'controle total ausente' })
            }
            foreach ($name in $expectation.Users) {
                $present = $null -ne ($identities | Where-Object { $_ -match "\\$([regex]::Escape($name))$" } | Select-Object -First 1)
                Add-Check -Status $(if ($present) { 'PASS' } else { 'FAIL' }) -Name "ACL $($expectation.Key)/$name" -Detail $(if ($present) { 'regra explicita presente' } else { 'regra esperada ausente' })
            }
            $expectedIdentityNames = @($systemName, $administratorsName) + @($expectation.Users | ForEach-Object { "$env:COMPUTERNAME\$_" })
            $unexpected = @($identities | Where-Object { $_ -notin $expectedIdentityNames })
            Add-Check -Status $(if ($unexpected.Count -eq 0) { 'PASS' } else { 'FAIL' }) -Name "ACL $($expectation.Key)/identidades" -Detail $(if ($unexpected.Count -eq 0) { 'sem acessos extras' } else { "acessos inesperados: $($unexpected -join ', ')" })
            if ($expectation.Key -eq 'PersonalData' -and $configuration.Accounts.Codex.Enabled) {
                $codexPresent = $null -ne ($identities | Where-Object { $_ -match "\\$([regex]::Escape([string]$configuration.Accounts.Codex.Name))$" } | Select-Object -First 1)
                Add-Check -Status $(if (-not $codexPresent) { 'PASS' } else { 'FAIL' }) -Name 'Isolamento dos dados pessoais' -Detail $(if ($codexPresent) { 'Codex possui acesso explicito' } else { 'Codex sem regra explicita' })
            }
        }
        catch { Add-Check -Status 'FAIL' -Name "ACL $($expectation.Key)" -Detail $_.Exception.Message }
    }
}

try {
    $uac = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -ErrorAction Stop).EnableLUA -eq 1
    Add-Check -Status $(if ($uac) { 'PASS' } else { 'FAIL' }) -Name 'UAC' -Detail $(if ($uac) { 'habilitado' } else { 'desabilitado' })
}
catch { Add-Check -Status 'WARN' -Name 'UAC' -Detail $_.Exception.Message }

try {
    $profiles = @(Get-NetFirewallProfile -ErrorAction Stop)
    $disabled = @($profiles | Where-Object { -not $_.Enabled })
    Add-Check -Status $(if ($disabled.Count -eq 0) { 'PASS' } else { 'FAIL' }) -Name 'Firewall' -Detail $(if ($disabled.Count -eq 0) { 'todos os perfis habilitados' } else { "perfis desabilitados: $($disabled.Name -join ', ')" })
}
catch { Add-Check -Status 'WARN' -Name 'Firewall' -Detail $_.Exception.Message }

try {
    $defender = Get-MpComputerStatus -ErrorAction Stop
    $ok = $defender.AntivirusEnabled -and $defender.RealTimeProtectionEnabled
    Add-Check -Status $(if ($ok) { 'PASS' } else { 'FAIL' }) -Name 'Microsoft Defender' -Detail "antivirus=$($defender.AntivirusEnabled); tempo real=$($defender.RealTimeProtectionEnabled)"
}
catch { Add-Check -Status 'WARN' -Name 'Microsoft Defender' -Detail $_.Exception.Message }

try {
    $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop
    Add-Check -Status $(if ($secureBoot) { 'PASS' } else { 'WARN' }) -Name 'Secure Boot' -Detail $(if ($secureBoot) { 'habilitado' } else { 'desabilitado' })
}
catch { Add-Check -Status 'WARN' -Name 'Secure Boot' -Detail $_.Exception.Message }

try {
    $tpm = Get-Tpm -ErrorAction Stop
    Add-Check -Status $(if ($tpm.TpmPresent -and $tpm.TpmReady) { 'PASS' } else { 'WARN' }) -Name 'TPM' -Detail "presente=$($tpm.TpmPresent); pronto=$($tpm.TpmReady)"
}
catch { Add-Check -Status 'WARN' -Name 'TPM' -Detail $_.Exception.Message }

if ($configuration.Security.ReportBitLockerStatus) {
    try {
        $volumes = @(Get-BitLockerVolume -ErrorAction Stop)
        $information.BitLocker = @($volumes | ForEach-Object { @{ MountPoint = $_.MountPoint; VolumeStatus = [string]$_.VolumeStatus; ProtectionStatus = [string]$_.ProtectionStatus } })
        Add-Check -Status 'INFO' -Name 'BitLocker' -Detail 'estado registrado; nao gerenciado por este setup'
    }
    catch { Add-Check -Status 'INFO' -Name 'BitLocker' -Detail "nao foi possivel consultar; nao e requisito: $($_.Exception.Message)" }
}

if ($configuration.Features.WSL) {
    if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
        & wsl.exe --status *> $null
        Add-Check -Status $(if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'WARN' }) -Name 'WSL' -Detail "wsl --status retornou $LASTEXITCODE"
    }
    else { Add-Check -Status 'FAIL' -Name 'WSL' -Detail 'wsl.exe ausente' }
}

if ($configuration.Packages.Enabled) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Add-Check -Status 'FAIL' -Name 'Winget' -Detail 'comando ausente'
    }
    else {
        foreach ($id in @(Get-PcSetupPackageIds -Configuration $configuration)) {
            & winget.exe list --id $id --exact --disable-interactivity *> $null
            Add-Check -Status $(if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'FAIL' }) -Name "Pacote $id" -Detail $(if ($LASTEXITCODE -eq 0) { 'instalado' } else { 'nao encontrado' })
        }
    }
}

try {
    $deviceErrors = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object Status -eq 'ERROR')
    if ($deviceErrors.Count -eq 0) { Add-Check -Status 'PASS' -Name 'Dispositivos' -Detail 'nenhum dispositivo presente com erro' }
    else {
        $information.DeviceErrors = @($deviceErrors | Select-Object Class, FriendlyName, InstanceId, Status)
        Add-Check -Status 'WARN' -Name 'Dispositivos' -Detail "$($deviceErrors.Count) dispositivo(s) presente(s) com erro"
    }
}
catch { Add-Check -Status 'WARN' -Name 'Dispositivos' -Detail $_.Exception.Message }

$summary = @{
    Pass = @($checks | Where-Object Status -eq 'PASS').Count
    Warn = @($checks | Where-Object Status -eq 'WARN').Count
    Fail = @($checks | Where-Object Status -eq 'FAIL').Count
    Info = @($checks | Where-Object Status -eq 'INFO').Count
}
$report = [ordered]@{
    GeneratedAt = (Get-Date).ToString('o')
    Profile     = $configuration.ProfileName
    Summary     = $summary
    Checks      = $checks
    Information = $information
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $reportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'ReportDirectory' -SystemRoot $(if ($storage) { $storage.SystemRoot } else { $null })
    $ReportPath = Join-Path $reportDirectory ('verify-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
}
Write-PcSetupJson -InputObject $report -Path $ReportPath | Out-Null
Write-Host "`nRelatorio: $ReportPath"
Write-Host "Resultado: PASS=$($summary.Pass), WARN=$($summary.Warn), FAIL=$($summary.Fail)"
if ($summary.Fail -gt 0) { exit 1 }
