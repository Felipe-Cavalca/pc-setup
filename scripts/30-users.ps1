#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [hashtable]$AccountPasswords = @{},
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
if ($mode -eq 'Apply') {
    Assert-PcSetupAdministrator
    $null = Enter-PcSetupProtectedScript -EntryPoint $MyInvocation.MyCommand.Name
}

$adminGroup = ([Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
$usersGroup = Get-LocalGroup -SID 'S-1-5-32-545' -ErrorAction Stop
$hyperVGroup = Get-LocalGroup -SID 'S-1-5-32-578' -ErrorAction SilentlyContinue
$hyperVAccountKeys = @($configuration.Security.HyperVAdministratorAccounts)
$results = @()

function Test-LocalAccountGroupMembership {
    param($User, [object[]]$Members)

    if (-not $User -or -not $User.SID) { return $false }
    return $null -ne ($Members | Where-Object { $_.SID -and $_.SID.Value -eq $User.SID.Value } | Select-Object -First 1)
}

foreach ($account in @(Get-PcSetupAccounts -Configuration $configuration)) {
    if (-not $account.Enabled) {
        Write-Host "[IGNORADO] Conta $($account.Name) desabilitada na configuracao."
        $results += [pscustomobject]@{ Name = $account.Name; Requested = $false; Action = 'None'; Role = $account.Role }
        continue
    }

    $user = Get-LocalUser -Name $account.Name -ErrorAction SilentlyContinue
    $usersMembers = @(Get-LocalGroupMember -Group $usersGroup -ErrorAction Stop)
    $isLocalUser = Test-LocalAccountGroupMembership -User $user -Members $usersMembers
    $members = @(Get-LocalGroupMember -Group $adminGroup -ErrorAction Stop)
    $isAdministrator = Test-LocalAccountGroupMembership -User $user -Members $members
    $targetAdministrator = $account.Role -eq 'Administrator'
    $hyperVMembers = if ($hyperVGroup) { @(Get-LocalGroupMember -Group $hyperVGroup.Name -ErrorAction Stop) } else { @() }
    $isHyperVAdministrator = Test-LocalAccountGroupMembership -User $user -Members $hyperVMembers
    $targetHyperVAdministrator = $hyperVAccountKeys -contains $account.Key

    if ($mode -eq 'Plan') {
        $actions = @()
        if (-not $user) { $actions += 'Create' }
        elseif (-not $user.Enabled) { $actions += 'Enable' }
        if (-not $isLocalUser) { $actions += 'AddToUsers' }
        if ($targetAdministrator -and -not $isAdministrator) { $actions += 'AddToAdministrators' }
        if (-not $targetAdministrator -and $isAdministrator) {
            if ($account.Key -eq 'DailyUser' -and -not $configuration.Security.DemoteDailyUserAutomatically) { $actions += 'ManualDemotionAfterAdminLoginTest' }
            else { $actions += 'RemoveFromAdministrators' }
        }
        if ($targetHyperVAdministrator -and -not $isHyperVAdministrator) { $actions += 'AddToHyperVAdministrators' }
        if (-not $targetHyperVAdministrator -and $isHyperVAdministrator) { $actions += 'RemoveFromHyperVAdministrators' }
        if ($actions.Count -eq 0) { $actions = @('None') }
        Write-Host "[PLANO] $($account.Name): $($actions -join ', ')."
        $results += [pscustomobject]@{ Name = $account.Name; Requested = $true; Action = ($actions -join ','); Role = $account.Role; LocalUsersGroup = $true; HyperVAdministrator = $targetHyperVAdministrator }
        continue
    }

    $accountAction = 'None'
    if (-not $user) {
        $password = $null
        if ($AccountPasswords.ContainsKey($account.Name)) { $password = $AccountPasswords[$account.Name] }
        if (-not ($password -is [securestring])) {
            $password = Read-Host "Defina a senha inicial para $($account.Name)" -AsSecureString
        }
        $user = New-LocalUser -Name $account.Name -Password $password -Description $account.Description -AccountNeverExpires -ErrorAction Stop
        $accountAction = 'Created'
        Write-Host "[CRIADO] Usuario $($account.Name)." -ForegroundColor Green
    }
    else {
        Write-Host "[OK] Usuario $($account.Name) ja existe."
    }
    if (-not $user.Enabled) {
        Enable-LocalUser -InputObject $user -ErrorAction Stop
        $user = Get-LocalUser -Name $account.Name -ErrorAction Stop
        $accountAction = 'Enabled'
        Write-Host "[HABILITADO] Usuario $($account.Name)." -ForegroundColor Green
    }

    $usersMembers = @(Get-LocalGroupMember -Group $usersGroup -ErrorAction Stop)
    $isLocalUser = Test-LocalAccountGroupMembership -User $user -Members $usersMembers
    $localUsersAction = 'None'
    if (-not $isLocalUser) {
        Add-LocalGroupMember -Group $usersGroup -Member $user -ErrorAction Stop
        $localUsersAction = 'AddedToUsers'
        Write-Host "[LOGON] Usuario $($account.Name) adicionado ao grupo local $($usersGroup.Name)." -ForegroundColor Green
    }

    $members = @(Get-LocalGroupMember -Group $adminGroup -ErrorAction Stop)
    $isAdministrator = Test-LocalAccountGroupMembership -User $user -Members $members
    $action = 'None'
    if ($targetAdministrator -and -not $isAdministrator) {
        Add-LocalGroupMember -Group $adminGroup -Member $user -ErrorAction Stop
        $action = 'AddedToAdministrators'
    }
    elseif (-not $targetAdministrator -and $isAdministrator) {
        if ($account.Key -eq 'DailyUser' -and -not $configuration.Security.DemoteDailyUserAutomatically) {
            Write-Warning "A conta diaria $($account.Name) continua administradora. Teste o login de $($configuration.Accounts.RecoveryAdmin.Name) e rebaixe-a manualmente."
            $action = 'ManualDemotionRequired'
        }
        else {
            Remove-LocalGroupMember -Group $adminGroup -Member $user -ErrorAction Stop
            $action = 'RemovedFromAdministrators'
        }
    }

    $hyperVAction = 'None'
    if ($targetHyperVAdministrator -and -not $hyperVGroup) { throw 'O grupo Hyper-V Administrators nao existe. Habilite o Hyper-V, reinicie e retome o setup.' }
    if ($hyperVGroup) {
        $hyperVMembers = @(Get-LocalGroupMember -Group $hyperVGroup.Name -ErrorAction Stop)
        $isHyperVAdministrator = Test-LocalAccountGroupMembership -User $user -Members $hyperVMembers
        if ($targetHyperVAdministrator -and -not $isHyperVAdministrator) {
            Add-LocalGroupMember -Group $hyperVGroup.Name -Member $user -ErrorAction Stop
            $hyperVAction = 'AddedToHyperVAdministrators'
        }
        elseif (-not $targetHyperVAdministrator -and $isHyperVAdministrator) {
            Remove-LocalGroupMember -Group $hyperVGroup.Name -Member $user -ErrorAction Stop
            $hyperVAction = 'RemovedFromHyperVAdministrators'
        }
    }
    $results += [pscustomobject]@{ Name = $account.Name; Requested = $true; AccountAction = $accountAction; LocalUsersGroup = $true; LocalUsersAction = $localUsersAction; Action = $action; Role = $account.Role; HyperVAdministrator = $targetHyperVAdministrator; HyperVAction = $hyperVAction }
}

[pscustomobject]@{ Step = 'Users'; Mode = $mode; Items = $results }
