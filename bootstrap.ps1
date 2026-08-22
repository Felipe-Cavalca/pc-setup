#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SkipUsers,
    [switch]$SkipPackages,
    [switch]$SkipWSL
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Assert-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Execute bootstrap.ps1 em um PowerShell elevado (Administrador).'
    }
}

function Invoke-Step([string]$Name, [string]$Script) {
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    & (Join-Path $root $Script)
}

Assert-Administrator

Invoke-Step 'Recursos do Windows' 'scripts\10-windows-features.ps1'
Invoke-Step 'Estrutura do disco D' 'scripts\20-directories.ps1'

if (-not $SkipUsers) {
    Invoke-Step 'Usuarios' 'scripts\30-users.ps1'
}

Invoke-Step 'Permissoes NTFS' 'scripts\40-permissions.ps1'

if (-not $SkipPackages) {
    Invoke-Step 'Pacotes base' 'scripts\60-packages.ps1'
}

if (-not $SkipWSL) {
    Invoke-Step 'WSL' 'scripts\70-wsl.ps1'
}

Write-Host "`nBootstrap base concluido." -ForegroundColor Green
Write-Host 'O debloat e propositalmente uma etapa explicita: .\scripts\50-debloat-akita.ps1'
Write-Host 'Reinicie o Windows se algum recurso opcional foi habilitado.'
Write-Host 'Depois execute .\verify.ps1'
