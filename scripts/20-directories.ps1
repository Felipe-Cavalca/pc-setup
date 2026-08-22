#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\machine.psd1'),
    [hashtable]$Storage,
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
if (-not $Storage) { $Storage = Resolve-PcSetupStorage -Configuration $configuration }
$paths = Get-PcSetupConfiguredPaths -Configuration $configuration -Storage $Storage

if ($mode -eq 'Apply') {
    Assert-PcSetupAdministrator
    $null = Enter-PcSetupProtectedScript -EntryPoint $MyInvocation.MyCommand.Name
}

$results = @()
foreach ($key in @($paths.Keys | Sort-Object)) {
    $path = $paths[$key]
    $exists = Test-Path -LiteralPath $path -PathType Container
    if ($exists) {
        Write-Host "[OK] $key -> $path"
        $action = 'None'
    }
    elseif ($mode -eq 'Plan') {
        Write-Host "[PLANO] Criar $key -> $path"
        $action = 'Create'
    }
    else {
        New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
        Write-Host "[CRIADO] $key -> $path" -ForegroundColor Green
        $action = 'Created'
    }
    $results += [pscustomobject]@{ Key = $key; Path = $path; Existed = $exists; Action = $action }
}

[pscustomobject]@{ Step = 'Directories'; Mode = $mode; DataRoot = $Storage.DataRoot; Items = $results }
