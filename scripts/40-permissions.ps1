#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [hashtable]$Storage,
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
if (-not $Storage) { $Storage = Resolve-PcSetupStorage -Configuration $configuration }
$paths = Get-PcSetupConfiguredPaths -Configuration $configuration -Storage $Storage
$primaryUser = [string]$configuration.Accounts.DailyUser.Name

$sharedGrants = @(@{ Identity = $primaryUser; Rights = 'Modify' })
if ($configuration.Accounts.Public.Enabled) {
    $sharedGrants += @{ Identity = [string]$configuration.Accounts.Public.Name; Rights = 'Modify' }
}
$targets = @(
    [pscustomobject]@{ Key = 'UserRoot'; Path = $paths.UserRoot; Grants = @(@{ Identity = $primaryUser; Rights = 'FullControl' }) },
    [pscustomobject]@{ Key = 'Shared'; Path = $paths.Shared; Grants = $sharedGrants }
)
if ($configuration.Backup.Enabled) {
    $targets += [pscustomobject]@{ Key = 'Backups'; Path = $paths[[string]$configuration.Backup.StagingPathKey]; Grants = @(@{ Identity = $primaryUser; Rights = 'FullControl' }) }
}

foreach ($target in $targets) {
    $grantsText = @($target.Grants | ForEach-Object { "$($_.Identity):$($_.Rights)" }) -join ', '
    Write-Host "[$($mode.ToUpperInvariant())] ACL $($target.Path): SYSTEM e Administradores FullControl; $grantsText."
}
if ($mode -eq 'Plan') {
    return [pscustomobject]@{ Step = 'Permissions'; Mode = $mode; BackupDirectory = $null; Items = $targets }
}

Assert-PcSetupAdministrator
$null = Enter-PcSetupProtectedScript -EntryPoint $MyInvocation.MyCommand.Name
if (-not $configuration.Security.BackupAclBeforeChanges) { throw 'Security.BackupAclBeforeChanges deve estar habilitado.' }

$backupRoot = Join-Path (Get-PcSetupRuntimePath -Configuration $configuration -Key 'StateDirectory' -SystemRoot $Storage.SystemRoot) ('acl-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backupRoot -Force -ErrorAction Stop | Out-Null
$backups = @()

function Invoke-IcaclsChecked {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & "$env:SystemRoot\System32\icacls.exe" @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "icacls falhou com codigo ${LASTEXITCODE}: $($Arguments -join ' ')" }
}

try {
    foreach ($target in $targets) {
        if (-not (Test-Path -LiteralPath $target.Path -PathType Container)) { throw "Diretorio ausente: $($target.Path). Rode 20-directories.ps1 primeiro." }
        $item = Get-Item -LiteralPath $target.Path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "ACL recusada em ponto de nova analise: $($target.Path)" }

        $backupFile = Join-Path $backupRoot ($target.Key + '.acl')
        Invoke-IcaclsChecked -Arguments @($target.Path, '/save', $backupFile, '/C', '/Q')
        $backups += [pscustomobject]@{ Key = $target.Key; Path = $target.Path; Parent = (Split-Path -Parent $target.Path); File = $backupFile }
    }

    foreach ($target in $targets) {
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        $propagation = [Security.AccessControl.PropagationFlags]::None
        $allow = [Security.AccessControl.AccessControlType]::Allow
        foreach ($rule in @(
            @{ Identity = [Security.Principal.SecurityIdentifier]'S-1-5-18'; Rights = [Security.AccessControl.FileSystemRights]::FullControl },
            @{ Identity = [Security.Principal.SecurityIdentifier]'S-1-5-32-544'; Rights = [Security.AccessControl.FileSystemRights]::FullControl }
        )) {
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($rule.Identity, $rule.Rights, $inheritance, $propagation, $allow)))
        }
        foreach ($grant in $target.Grants) {
            $identity = New-Object Security.Principal.NTAccount($env:COMPUTERNAME, [string]$grant.Identity)
            $rights = [Security.AccessControl.FileSystemRights]$grant.Rights
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity, $rights, $inheritance, $propagation, $allow)))
        }
        Set-Acl -LiteralPath $target.Path -AclObject $acl -ErrorAction Stop
        Write-Host "[OK] ACL aplicada em $($target.Path)." -ForegroundColor Green
    }
}
catch {
    $applyError = $_
    Write-Warning 'Falha ao aplicar ACL. Tentando restaurar todos os backups desta execucao.'
    foreach ($backup in @($backups | Sort-Object Path -Descending)) {
        try { Invoke-IcaclsChecked -Arguments @($backup.Parent, '/restore', $backup.File, '/C', '/Q') }
        catch { Write-Warning "Falha no rollback de $($backup.Path): $($_.Exception.Message)" }
    }
    throw $applyError
}

$manifestPath = Join-Path $backupRoot 'manifest.json'
Write-PcSetupJson -InputObject @{ CreatedAt = (Get-Date).ToString('o'); Items = $backups } -Path $manifestPath | Out-Null
[pscustomobject]@{ Step = 'Permissions'; Mode = $mode; BackupDirectory = $backupRoot; Manifest = $manifestPath; Items = $targets }
