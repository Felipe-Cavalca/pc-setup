#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = (Join-Path $PSScriptRoot 'config\machine.psd1'),
    [string]$ReportPath = ''
)

$ErrorActionPreference = 'Continue'
$coreModule = Join-Path $PSScriptRoot 'scripts\lib\PcSetup.Core.psm1'
$wslModule = Join-Path $PSScriptRoot 'wsl\PcSetup.Wsl.psm1'
Import-Module $coreModule -Force
Import-Module $wslModule -Force
$configuration = Import-PcSetupConfiguration -Path $Config
Assert-PcSetupAdministrator
$configHash = (Get-FileHash -LiteralPath $configuration._ConfigPath -Algorithm SHA256).Hash
$projectHash = Get-PcSetupProjectFingerprint -Configuration $configuration

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
    $windows = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $editionOk = [string]$windows.EditionID -eq [string]$configuration.Windows.Edition
    Add-Check -Status $(if ($editionOk) { 'PASS' } else { 'FAIL' }) -Name 'Edicao do Windows' -Detail "EditionID=$($windows.EditionID); produto=$($computerInfo.WindowsProductName)"
    $build = [int]$windows.CurrentBuildNumber
    if ([string]::IsNullOrWhiteSpace([string]$configuration.Windows.TargetVersion)) {
        Add-Check -Status 'PASS' -Name 'Versao do Windows' -Detail "qualquer versao do Windows 11 aceita; encontrada $($windows.DisplayVersion)"
    }
    else {
        Add-Check -Status $(if ($windows.DisplayVersion -eq $configuration.Windows.TargetVersion) { 'PASS' } else { 'FAIL' }) -Name 'Versao do Windows' -Detail "esperada $($configuration.Windows.TargetVersion); encontrada $($windows.DisplayVersion)"
    }
    Add-Check -Status $(if ($build -ge [int]$configuration.Windows.MinimumBuild) { 'PASS' } else { 'FAIL' }) -Name 'Build do Windows' -Detail "minima $($configuration.Windows.MinimumBuild); encontrada $build"
}
catch { Add-Check -Status 'FAIL' -Name 'Windows' -Detail $_.Exception.Message }

$desiredComputerName = [string]$configuration.Machine.ComputerName
if ([string]::IsNullOrWhiteSpace($desiredComputerName)) {
    Add-Check -Status 'INFO' -Name 'Nome do computador' -Detail "preservado pela configuracao; atual=$env:COMPUTERNAME"
}
else {
    Add-Check -Status $(if ($env:COMPUTERNAME -eq $desiredComputerName) { 'PASS' } else { 'FAIL' }) -Name 'Nome do computador' -Detail "esperado=$desiredComputerName; atual=$env:COMPUTERNAME"
}

try {
    $licensing = Get-CimInstance SoftwareLicensingProduct -Filter "Name like 'Windows%' and PartialProductKey is not null" -ErrorAction Stop | Where-Object LicenseStatus -eq 1 | Select-Object -First 1
    Add-Check -Status $(if ($licensing) { 'PASS' } else { 'WARN' }) -Name 'Ativacao' -Detail $(if ($licensing) { 'Windows ativado' } else { 'licenca ativa nao encontrada' })
}
catch { Add-Check -Status 'WARN' -Name 'Ativacao' -Detail $_.Exception.Message }

$storage = $null
$paths = $null
$systemRoot = [IO.Path]::GetPathRoot($env:SystemRoot)
$runtimeReportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'ReportDirectory' -SystemRoot $systemRoot
$latestApplyReportFile = Get-ChildItem -LiteralPath $runtimeReportDirectory -Filter 'pc-setup-apply-*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$latestApplyReport = $null
if ($latestApplyReportFile) {
    try { $latestApplyReport = Get-Content -LiteralPath $latestApplyReportFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Add-Check -Status 'FAIL' -Name 'Relatorio de aplicacao/formato' -Detail $_.Exception.Message }
}
$selectedDataRoot = ''
if ($latestApplyReport -and $latestApplyReport.Status -eq 'Completed' -and $latestApplyReport.ConfigSha256 -eq $configHash) {
    $selectedDataRoot = [string]$latestApplyReport.Storage.DataRoot
}
try {
    if ($configuration.Storage.Data.SecondaryDiskPolicy -eq 'Ask' -and [string]::IsNullOrWhiteSpace($selectedDataRoot)) {
        throw 'Nao ha relatorio concluido desta configuracao com a escolha do armazenamento. Execute INSTALAR.cmd ou ATUALIZAR.cmd.'
    }
    $storage = Resolve-PcSetupStorage -Configuration $configuration -SelectedDataRoot $selectedDataRoot
    $paths = Get-PcSetupConfiguredPaths -Configuration $configuration -Storage $storage
    Add-Check -Status 'PASS' -Name 'Armazenamento' -Detail "Windows=$($storage.SystemRoot); dados=$($storage.DataRoot); modo=$($storage.DataMode)"
}
catch { Add-Check -Status 'FAIL' -Name 'Armazenamento' -Detail $_.Exception.Message }

try {
    if (-not $latestApplyReportFile) {
        Add-Check -Status 'WARN' -Name 'Relatorio de aplicacao' -Detail 'nenhum relatorio Apply encontrado'
    }
    else {
        Add-Check -Status $(if ($latestApplyReport.Status -eq 'Completed') { 'PASS' } else { 'FAIL' }) -Name 'Aplicacao concluida' -Detail "$($latestApplyReport.Status); $($latestApplyReportFile.FullName)"
        Add-Check -Status $(if ($latestApplyReport.ConfigSha256 -eq $configHash) { 'PASS' } else { 'FAIL' }) -Name 'Configuracao aplicada' -Detail $(if ($latestApplyReport.ConfigSha256 -eq $configHash) { $configHash } else { 'o relatorio pertence a outra configuracao' })
        Add-Check -Status $(if ($latestApplyReport.ProjectSha256 -eq $projectHash) { 'PASS' } else { 'WARN' }) -Name 'Versao do projeto aplicada' -Detail $(if ($latestApplyReport.ProjectSha256 -eq $projectHash) { $projectHash } else { 'o projeto mudou depois da ultima aplicacao' })
        $recoveryValidated = $latestApplyReport.Recovery -and $latestApplyReport.Recovery.Validated -eq $true -and $latestApplyReport.Recovery.SequenceNumber
        Add-Check -Status $(if ($recoveryValidated) { 'PASS' } else { 'WARN' }) -Name 'Ponto de restauracao da aplicacao' -Detail $(if ($recoveryValidated) { "sequencia=$($latestApplyReport.Recovery.SequenceNumber)" } else { 'relatorio sem comprovante de recuperacao; execute uma nova aplicacao com a versao atual' })
    }
}
catch { Add-Check -Status 'WARN' -Name 'Relatorio de aplicacao' -Detail $_.Exception.Message }

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
    $hyperVGroup = Get-LocalGroup -SID 'S-1-5-32-578' -ErrorAction SilentlyContinue
    $hyperVMembers = if ($hyperVGroup) { @(Get-LocalGroupMember -Group $hyperVGroup.Name -ErrorAction Stop) } else { @() }
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
        $shouldManageHyperV = @($configuration.Security.HyperVAdministratorAccounts) -contains $account.Key
        $managesHyperV = $null -ne ($hyperVMembers | Where-Object { $_.Name -match "\\$([regex]::Escape($account.Name))$" } | Select-Object -First 1)
        Add-Check -Status $(if ($shouldManageHyperV -eq $managesHyperV) { 'PASS' } else { 'FAIL' }) -Name "Hyper-V $($account.Name)" -Detail $(if ($managesHyperV) { 'membro de Hyper-V Administrators' } else { 'sem associacao explicita ao Hyper-V' })
    }
    if (@($configuration.Security.HyperVAdministratorAccounts).Count -gt 0 -and -not $hyperVGroup) { Add-Check -Status 'FAIL' -Name 'Hyper-V Administrators' -Detail 'grupo local ausente' }
}
catch { Add-Check -Status 'FAIL' -Name 'Usuarios locais' -Detail $_.Exception.Message }

if ($paths) {
    foreach ($key in @($paths.Keys | Sort-Object)) {
        Add-Check -Status $(if (Test-Path -LiteralPath $paths[$key] -PathType Container) { 'PASS' } else { 'FAIL' }) -Name "Diretorio $key" -Detail $paths[$key]
    }

    $developmentGrants = @(@{ Name = [string]$configuration.Accounts.DailyUser.Name; Rights = 'Modify' })
    $aclExpectations = @(
        @{ Key = 'Development'; Grants = $developmentGrants },
        @{ Key = 'PersonalData'; Grants = @(@{ Name = [string]$configuration.Accounts.DailyUser.Name; Rights = 'FullControl' }) }
    )
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
                $fullControl = $null -ne ($allowRules | Where-Object {
                    $_.IdentityReference.Value -eq $builtIn -and
                    -not $_.IsInherited -and
                    $_.FileSystemRights -eq [Security.AccessControl.FileSystemRights]::FullControl -and
                    ($_.InheritanceFlags -band [Security.AccessControl.InheritanceFlags]::ContainerInherit) -ne 0 -and
                    ($_.InheritanceFlags -band [Security.AccessControl.InheritanceFlags]::ObjectInherit) -ne 0 -and
                    $_.PropagationFlags -eq [Security.AccessControl.PropagationFlags]::None
                } | Select-Object -First 1)
                Add-Check -Status $(if ($fullControl) { 'PASS' } else { 'FAIL' }) -Name "ACL $($expectation.Key)/$builtIn" -Detail $(if ($fullControl) { 'controle total explicito e herdavel' } else { 'regra exata de controle total ausente' })
            }
            foreach ($grant in $expectation.Grants) {
                $name = [string]$grant.Name
                $expectedRights = [Security.AccessControl.FileSystemRights]$grant.Rights
                $matchingRules = @($allowRules | Where-Object { $_.IdentityReference.Value -match "\\$([regex]::Escape($name))$" })
                $validRule = $null -ne ($matchingRules | Where-Object {
                    -not $_.IsInherited -and
                    $_.FileSystemRights -eq $expectedRights -and
                    ($_.InheritanceFlags -band [Security.AccessControl.InheritanceFlags]::ContainerInherit) -ne 0 -and
                    ($_.InheritanceFlags -band [Security.AccessControl.InheritanceFlags]::ObjectInherit) -ne 0 -and
                    $_.PropagationFlags -eq [Security.AccessControl.PropagationFlags]::None
                } | Select-Object -First 1)
                $detail = if ($validRule) { "$($grant.Rights) explicito e herdavel" } elseif ($matchingRules.Count -gt 0) { "regra presente com direitos ou heranca diferentes de $($grant.Rights)" } else { 'regra esperada ausente' }
                Add-Check -Status $(if ($validRule) { 'PASS' } else { 'FAIL' }) -Name "ACL $($expectation.Key)/$name" -Detail $detail
            }
            $expectedIdentityNames = @($systemName, $administratorsName) + @($expectation.Grants | ForEach-Object { "$env:COMPUTERNAME\$($_.Name)" })
            $unexpected = @($identities | Where-Object { $_ -notin $expectedIdentityNames })
            Add-Check -Status $(if ($unexpected.Count -eq 0) { 'PASS' } else { 'FAIL' }) -Name "ACL $($expectation.Key)/identidades" -Detail $(if ($unexpected.Count -eq 0) { 'sem acessos extras' } else { "acessos inesperados: $($unexpected -join ', ')" })
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
        try {
            $installedDistributions = @(Get-PcSetupWslDistributionNames)
            foreach ($environmentDefinition in @(Get-PcSetupWslEnvironments -Configuration $configuration | Where-Object Enabled)) {
                if ($environmentDefinition.WindowsAccount -ne $env:USERNAME) {
                    Add-Check -Status 'INFO' -Name "WSL $($environmentDefinition.Name)" -Detail "verifique na sessao Windows de $($environmentDefinition.WindowsAccount) com .\wsl\verify.ps1 -Environment $($environmentDefinition.Name)"
                    continue
                }
                $distribution = [string]$environmentDefinition.Distribution
                if ($installedDistributions -notcontains $distribution) {
                    Add-Check -Status 'WARN' -Name "WSL $($environmentDefinition.Name)" -Detail "distribuicao ausente para $env:USERNAME; execute .\wsl\bootstrap.ps1 -Environment $($environmentDefinition.Name) -Apply"
                    continue
                }
                $actualWslVersion = Get-PcSetupWslDistributionVersion -Distribution $distribution
                Add-Check -Status $(if ($actualWslVersion -eq [int]$configuration.WSL.DefaultVersion) { 'PASS' } else { 'FAIL' }) -Name "WSL $($environmentDefinition.Name)/versao" -Detail "esperada=$($configuration.WSL.DefaultVersion); atual=$actualWslVersion"
                $wslProfile = Import-PcSetupWslProfile -Configuration $configuration -Environment $environmentDefinition
                $defaultWslUser = Get-PcSetupWslDefaultUser -Distribution $distribution
                $expectedDefaultWslUser = Get-PcSetupExpectedWslDefaultUser -Configuration $configuration -Environment $environmentDefinition
                Add-Check -Status $(if ($defaultWslUser -eq $expectedDefaultWslUser) { 'PASS' } else { 'FAIL' }) -Name "WSL $($environmentDefinition.Name)/usuario padrao" -Detail "esperado=$expectedDefaultWslUser; atual=$defaultWslUser"
                $verifyLinuxPath = ConvertTo-PcSetupWslPath -Distribution $distribution -WindowsPath (Join-Path $PSScriptRoot 'wsl\linux\verify.sh')
                $wslVerifyResult = Invoke-PcSetupWslLinuxScript -Distribution $distribution -ScriptPath $verifyLinuxPath -Environment $environmentDefinition -Profile $wslProfile
                Add-Check -Status $(if ($wslVerifyResult.ExitCode -eq 0) { 'PASS' } else { 'FAIL' }) -Name "WSL $($environmentDefinition.Name)/conteudo" -Detail $(if ($wslVerifyResult.ExitCode -eq 0) { 'usuario, diretorio e pacotes conferidos' } else { "verify Linux retornou $($wslVerifyResult.ExitCode)" })
            }
        }
        catch { Add-Check -Status 'FAIL' -Name 'Ambientes WSL' -Detail $_.Exception.Message }
    }
    else { Add-Check -Status 'FAIL' -Name 'WSL' -Detail 'wsl.exe ausente' }
}

if ($configuration.Packages.Enabled) {
    Add-Check -Status 'INFO' -Name 'Pacotes Winget' -Detail 'instalados, inventariados e validados sem elevacao na fase da conta diaria'
}

if ($configuration.Personalization.Enabled) {
    Add-Check -Status 'INFO' -Name 'Personalizacao' -Detail 'aplicada e validada sem elevacao na fase da conta diaria; consulte o relatorio user-profile em LOCALAPPDATA'
}
else {
    Add-Check -Status 'INFO' -Name 'Personalizacao' -Detail 'nao solicitada pela configuracao'
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
