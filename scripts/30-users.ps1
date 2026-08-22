#requires -RunAsAdministrator

function Ensure-User([string]$Name, [bool]$Administrator) {
    $user = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
    if (-not $user) {
        Write-Host "Criando usuario $Name"
        $password = Read-Host "Defina a senha inicial para $Name" -AsSecureString
        New-LocalUser -Name $Name -Password $password -PasswordNeverExpires:$false -AccountNeverExpires | Out-Null
    } else {
        Write-Host "[OK] Usuario $Name ja existe"
    }

    if ($Administrator) {
        $member = Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | Where-Object Name -Match "\\$([regex]::Escape($Name))$"
        if (-not $member) { Add-LocalGroupMember -Group 'Administrators' -Member $Name }
    } else {
        Remove-LocalGroupMember -Group 'Administrators' -Member $Name -ErrorAction SilentlyContinue
    }
}

Ensure-User 'Admin' $true
Ensure-User 'Codex' $false
Ensure-User 'God' $true
Ensure-User 'Publico' $false

Write-Warning 'Este script NAO remove Felipe de Administrators. Entre e teste Admin primeiro; so depois rebaixe Felipe manualmente para Standard.'
