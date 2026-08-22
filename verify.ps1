#requires -Version 5.1
$ErrorActionPreference = 'Continue'

$fail = 0
function Result($ok, $text) {
    if ($ok) { Write-Host "[OK]   $text" -ForegroundColor Green }
    else { Write-Host "[FAIL] $text" -ForegroundColor Red; $script:fail++ }
}

Write-Host '=== pc-setup verify ===' -ForegroundColor Cyan

$edition = (Get-ComputerInfo -Property WindowsProductName).WindowsProductName
Result ($edition -match 'Pro') "Windows Pro ($edition)"

$windows = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$displayVersion = $windows.DisplayVersion
$currentBuild = [int]$windows.CurrentBuildNumber
Result ($displayVersion -eq '25H2') "Windows target 25H2 (detectado: $displayVersion)"
Result ($currentBuild -ge 26200) "Build Windows >= 26200 (detectado: $currentBuild)"

foreach ($feature in @('Microsoft-Hyper-V-All','Containers-DisposableClientVM','VirtualMachinePlatform','Microsoft-Windows-Subsystem-Linux')) {
    $f = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
    Result ($f.State -eq 'Enabled') "$feature habilitado"
}

$adminGroup = ([System.Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
$adminMembers = Get-LocalGroupMember -Group $adminGroup -ErrorAction SilentlyContinue

$expectedUsers = @{
    'Admin'='Administrator'
    'Codex'='Standard'
    'God'='Administrator'
    'Publico'='Standard'
}

foreach ($name in $expectedUsers.Keys) {
    $u = Get-LocalUser -Name $name -ErrorAction SilentlyContinue
    Result ($null -ne $u) "Usuario $name existe"
    if ($u) {
        $isAdmin = $null -ne ($adminMembers | Where-Object Name -Match "\\$([regex]::Escape($name))$")
        if ($expectedUsers[$name] -eq 'Administrator') { Result $isAdmin "$name e administrador" }
        else { Result (-not $isAdmin) "$name nao e administrador" }
    }
}

foreach ($path in @('D:\Apps','D:\Games','D:\Dev','D:\Data\Felipe','D:\Shared','D:\VMs','D:\Containers','D:\Agent\Codex')) {
    Result (Test-Path $path) "$path existe"
}

if (Test-Path 'D:\Dev') {
    $acl = Get-Acl 'D:\Dev'
    Result (($acl.Access.IdentityReference.Value -match '\\Codex$').Count -gt 0) 'ACL de D:\Dev referencia Codex'
}

if (Test-Path 'D:\Data\Felipe') {
    $acl = Get-Acl 'D:\Data\Felipe'
    Result (($acl.Access.IdentityReference.Value -match '\\Codex$').Count -eq 0) 'D:\Data\Felipe nao concede regra explicita ao Codex'
}

try {
    $bl = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop
    Result ($bl.ProtectionStatus -eq 'On') 'BitLocker C protegido'
} catch { Write-Host '[WARN] Nao foi possivel validar BitLocker C' -ForegroundColor Yellow }

if (Test-Path 'D:\') {
    try {
        $bl = Get-BitLockerVolume -MountPoint 'D:' -ErrorAction Stop
        Result ($bl.ProtectionStatus -eq 'On') 'BitLocker D protegido'
    } catch { Write-Host '[WARN] Nao foi possivel validar BitLocker D' -ForegroundColor Yellow }
}

if ($fail -gt 0) {
    Write-Host "`nResultado: $fail verificacao(oes) falharam." -ForegroundColor Red
    exit 1
}

Write-Host "`nResultado: PASS" -ForegroundColor Green
