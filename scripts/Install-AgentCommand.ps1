#requires -Version 5.1
[CmdletBinding()]
param([string]$Config = '', [switch]$Plan, [switch]$Apply)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path $root 'config\machine.psd1' }
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1') -Force
$mode = Get-PcSetupExecutionMode -Plan:$Plan -Apply:$Apply
$configuration = Import-PcSetupConfiguration -Path $Config
if ($env:USERNAME -ne [string]$configuration.Accounts.DailyUser.Name) { throw 'O comando agente deve ser instalado pela conta Windows diaria.' }

$binDirectory = Join-Path $env:LOCALAPPDATA 'pc-setup\bin'
$shimPath = Join-Path $binDirectory 'agente.cmd'
$existing = @(Get-Command agente -All -ErrorAction SilentlyContinue | Where-Object {
    $candidatePath = if ([string]::IsNullOrWhiteSpace([string]$_.Path)) { [string]$_.Source } else { [string]$_.Path }
    [string]::IsNullOrWhiteSpace($candidatePath) -or [IO.Path]::GetFullPath($candidatePath) -ne [IO.Path]::GetFullPath($shimPath)
})
if ($existing.Count -gt 0) {
    $description = if ([string]::IsNullOrWhiteSpace([string]$existing[0].Source)) { [string]$existing[0].CommandType } else { [string]$existing[0].Source }
    throw "Ja existe outro comando agente no PATH: $description. Nada foi sobrescrito."
}

if ($mode -eq 'Plan') {
    Write-Host "[PLANO] Instalar agente em $shimPath e adicionar somente essa pasta ao PATH do usuario."
    return [pscustomobject]@{ Step = 'AgentCommand'; Mode = $mode; Path = $shimPath; Action = 'Plan' }
}

New-Item -ItemType Directory -Path $binDirectory -Force | Out-Null
$launcher = Join-Path $PSScriptRoot 'Invoke-AgentCommand.cmd'
$content = "@echo off`r`ncall `"$launcher`" %*`r`nexit /b %errorlevel%`r`n"
[IO.File]::WriteAllText($shimPath, $content, [Text.Encoding]::ASCII)
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($entries -notcontains $binDirectory) { [Environment]::SetEnvironmentVariable('Path', (($entries + $binDirectory) -join ';'), 'User') }
Write-Host "[OK] Comando agente instalado em $shimPath. Abra um novo terminal para atualizar o PATH." -ForegroundColor Green
[pscustomobject]@{ Step = 'AgentCommand'; Mode = $mode; Path = $shimPath; Action = 'Installed' }
