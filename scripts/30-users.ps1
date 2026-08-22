#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\machine.psd1'),
    [hashtable]$AccountPasswords = @{},
    [switch]$Plan,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
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

$adminGroup = ([Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
$results = @()
foreach ($account in @(Get-PcSetupAccounts -Configuration $configuration)) {
    if (-not $account.Enabled) {
        Write-Host "[IGNORADO] Conta $($account.Name) desabilitada na configuracao."
        $results += [pscustomobject]@{ Name = $account.Name; Requested = $false; Action = 'None'; Role = $account.Role }
        continue
    }

    $user = Get-LocalUser -Name $account.Name -ErrorAction SilentlyContinue
    $members = @(Get-LocalGroupMember -Group $adminGroup -ErrorAction Stop)
    $isAdministrator = $null -ne ($members | Where-Object { $_.Name -match "\\$([regex]::Escape($account.Name))$" } | Select-Object -First 1)
    $targetAdministrator = $account.Role -eq 'Administrator'

    if ($mode -eq 'Plan') {
        $actions = @()
        if (-not $user) { $actions += 'Create' }
        if ($targetAdministrator -and -not $isAdministrator) { $actions += 'AddToAdministrators' }
        if (-not $targetAdministrator -and $isAdministrator) {
            if ($account.Key -eq 'DailyUser' -and -not $configuration.Security.DemoteDailyUserAutomatically) { $actions += 'ManualDemotionAfterAdminLoginTest' }
            else { $actions += 'RemoveFromAdministrators' }
        }
        if ($actions.Count -eq 0) { $actions = @('None') }
        Write-Host "[PLANO] $($account.Name): $($actions -join ', ')."
        $results += [pscustomobject]@{ Name = $account.Name; Requested = $true; Action = ($actions -join ','); Role = $account.Role }
        continue
    }

    if (-not $user) {
        $password = $null
        if ($AccountPasswords.ContainsKey($account.Name)) { $password = $AccountPasswords[$account.Name] }
        if (-not ($password -is [securestring])) {
            $password = Read-Host "Defina a senha inicial para $($account.Name)" -AsSecureString
        }
        New-LocalUser -Name $account.Name -Password $password -Description $account.Description -AccountNeverExpires -ErrorAction Stop | Out-Null
        Write-Host "[CRIADO] Usuario $($account.Name)." -ForegroundColor Green
    }
    else {
        Write-Host "[OK] Usuario $($account.Name) ja existe."
    }

    $members = @(Get-LocalGroupMember -Group $adminGroup -ErrorAction Stop)
    $isAdministrator = $null -ne ($members | Where-Object { $_.Name -match "\\$([regex]::Escape($account.Name))$" } | Select-Object -First 1)
    $action = 'None'
    if ($targetAdministrator -and -not $isAdministrator) {
        Add-LocalGroupMember -Group $adminGroup -Member $account.Name -ErrorAction Stop
        $action = 'AddedToAdministrators'
    }
    elseif (-not $targetAdministrator -and $isAdministrator) {
        if ($account.Key -eq 'DailyUser' -and -not $configuration.Security.DemoteDailyUserAutomatically) {
            Write-Warning "A conta diaria $($account.Name) continua administradora. Teste o login de $($configuration.Accounts.RecoveryAdmin.Name) e rebaixe-a manualmente."
            $action = 'ManualDemotionRequired'
        }
        else {
            Remove-LocalGroupMember -Group $adminGroup -Member $account.Name -ErrorAction Stop
            $action = 'RemovedFromAdministrators'
        }
    }
    $results += [pscustomobject]@{ Name = $account.Name; Requested = $true; Action = $action; Role = $account.Role }
}

[pscustomobject]@{ Step = 'Users'; Mode = $mode; Items = $results }
