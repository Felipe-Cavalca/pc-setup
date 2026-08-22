#requires -RunAsAdministrator

$adminGroup = ([System.Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]

function Ensure-User([string]$Name, [bool]$Administrator) {
    $user = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
    if (-not $user) {
        Write-Host "Criando usuario $Name"
        $password = Read-Host "Defina a senha inicial para $Name" -AsSecureString
        New-LocalUser -Name $Name -Password $password -PasswordNeverExpires:$false -AccountNeverExpires | Out-Null
    } else {
        Write-Host "[OK] Usuario $Name ja existe"
    }

    $member = Get-LocalGroupMember -Group $adminGroup -ErrorAction SilentlyContinue | Where-Object Name -Match "\\$([regex]::Escape($Name))$"
    if ($Administrator -and -not $member) {
        Add-LocalGroupMember -Group $adminGroup -Member $Name
    }
    if ((-not $Administrator) -and $member) {
        Remove-LocalGroupMember -Group $adminGroup -Member $Name
    }
}

Ensure-User 'Admin' $true
Ensure-User 'Codex' $false
Ensure-User 'God' $true
Ensure-User 'Publico' $false

Write-Warning 'Este script NAO remove Felipe do grupo administrativo. Entre e teste Admin primeiro; so depois rebaixe Felipe manualmente para Standard.'
