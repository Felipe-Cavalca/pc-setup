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
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Recovery.psm1') -Force

$mode = Get-PcSetupExecutionMode -Plan:$Plan -Apply:$Apply
$configuration = Import-PcSetupConfiguration -Path $Config
if (-not $Storage) { $Storage = Resolve-PcSetupStorage -Configuration $configuration }
$paths = Get-PcSetupConfiguredPaths -Configuration $configuration -Storage $Storage

if ($mode -eq 'Apply') {
    Assert-PcSetupAdministrator
    $null = Enter-PcSetupProtectedScript -EntryPoint $MyInvocation.MyCommand.Name
}

$results = @()
foreach ($name in @('HyperV','Docker','Steam','Epic')) {
    $integration = $configuration.Storage.Integrations[$name]
    $target = [string]$paths[[string]$integration.PathKey]
    if (-not $integration.Enabled) {
        $results += [pscustomobject]@{ Name = $name; Enabled = $false; Mode = [string]$integration.Mode; Target = $target; Status = 'Disabled'; Action = 'None' }
        continue
    }

    if ($name -eq 'HyperV' -and [string]$integration.Mode -eq 'Automatic') {
        $vhdPath = Join-Path $target 'Virtual Hard Disks'
        if ($mode -eq 'Plan') {
            Write-Host "[PLANO] Configurar os novos discos e VMs do Hyper-V em $target."
            $results += [pscustomobject]@{ Name = $name; Enabled = $true; Mode = 'Automatic'; Target = $target; VirtualHardDiskPath = $vhdPath; Status = 'Planned'; Action = 'Configure' }
            continue
        }
        if (-not (Get-Command Get-VMHost -ErrorAction SilentlyContinue) -or -not (Get-Command Set-VMHost -ErrorAction SilentlyContinue)) {
            throw 'Os cmdlets do Hyper-V nao estao disponiveis depois da habilitacao do recurso.'
        }
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        New-Item -ItemType Directory -Path $vhdPath -Force | Out-Null
        $hostSettings = Get-VMHost -ErrorAction Stop
        $needsChange =
            [IO.Path]::GetFullPath([string]$hostSettings.VirtualMachinePath).TrimEnd('\') -ne [IO.Path]::GetFullPath($target).TrimEnd('\') -or
            [IO.Path]::GetFullPath([string]$hostSettings.VirtualHardDiskPath).TrimEnd('\') -ne [IO.Path]::GetFullPath($vhdPath).TrimEnd('\')
        if ($needsChange) {
            Set-VMHost -VirtualMachinePath $target -VirtualHardDiskPath $vhdPath -ErrorAction Stop | Out-Null
            $action = 'Configured'
        }
        else { $action = 'None' }
        Write-Host "[OK] Hyper-V: VMs=$target; VHDs=$vhdPath." -ForegroundColor Green
        $results += [pscustomobject]@{ Name = $name; Enabled = $true; Mode = 'Automatic'; Target = $target; VirtualHardDiskPath = $vhdPath; Status = 'Configured'; Action = $action }
        continue
    }

    $instruction = switch ($name) {
        'Docker' { 'No Docker Desktop: Settings > Resources > Advanced > Disk image location.' }
        'Steam'  { 'No Steam: Configuracoes > Armazenamento > + e selecione a pasta.' }
        'Epic'   { 'No Epic Games Launcher, escolha esta pasta ao instalar cada jogo.' }
        default  { 'Configure manualmente no aplicativo.' }
    }
    Write-Host "[MANUAL] $name -> $target. $instruction" -ForegroundColor Yellow
    $results += [pscustomobject]@{ Name = $name; Enabled = $true; Mode = 'ManualRequired'; Target = $target; Status = 'ManualRequired'; Action = 'None'; Instruction = $instruction }
}

[pscustomobject]@{ Step = 'StorageIntegrations'; Mode = $mode; Items = $results }
