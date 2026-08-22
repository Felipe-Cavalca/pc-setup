#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\machine.psd1'),
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
if (-not $configuration.Personalization.Enabled) {
    Write-Host '[IGNORADO] Personalizacao desabilitada ou sem imagem revisada.'
    return [pscustomobject]@{ Step = 'Personalization'; Mode = $mode; Enabled = $false; Action = 'None' }
}
if ([string]::IsNullOrWhiteSpace([string]$configuration.Personalization.WallpaperPath)) { throw 'Personalization.WallpaperPath nao pode ficar vazio quando a personalizacao esta habilitada.' }

$sourcePath = Resolve-PcSetupProjectPath -Configuration $configuration -Value ([string]$configuration.Personalization.WallpaperPath) -SettingName 'Personalization.WallpaperPath'
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Arquivo de plano de fundo ausente: $sourcePath" }

if ($mode -eq 'Plan') {
    Write-Host "[PLANO] Copiar e aplicar o plano de fundo para o usuario atual: $sourcePath"
    return [pscustomobject]@{ Step = 'Personalization'; Mode = $mode; Enabled = $true; Source = $sourcePath; Action = 'SetWallpaperForCurrentUser' }
}

Assert-PcSetupAdministrator
$null = Enter-PcSetupProtectedScript -EntryPoint $MyInvocation.MyCommand.Name
$stateRoot = Get-PcSetupRuntimePath -Configuration $configuration -Key 'StateDirectory'
$assetDirectory = Join-Path $stateRoot 'assets'
New-Item -ItemType Directory -Path $assetDirectory -Force | Out-Null
$targetPath = Join-Path $assetDirectory ('wallpaper' + [IO.Path]::GetExtension($sourcePath))
Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force

Set-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value $targetPath
Set-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'
Set-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0'
if (-not ('PcSetup.NativeMethods' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace PcSetup {
    public static class NativeMethods {
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool SystemParametersInfo(int action, int parameter, string value, int flags);
    }
}
'@
}
$updated = [PcSetup.NativeMethods]::SystemParametersInfo(20, 0, $targetPath, 3)
if (-not $updated) { throw 'O arquivo foi configurado, mas o Windows nao confirmou a atualizacao imediata do plano de fundo.' }

[pscustomobject]@{ Step = 'Personalization'; Mode = $mode; Enabled = $true; Source = $sourcePath; Target = $targetPath; Action = 'Completed' }
