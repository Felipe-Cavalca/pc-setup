#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [string]$ProjectPath = '',
    [string]$Command = '',
    [ValidateSet('Direct','Managed','Review','Private')]
    [string]$Mode = '',
    [Alias('sem-memoria')][switch]$WithoutMemory,
    [Alias('nova')][switch]$Fresh
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path $root 'config\machine.psd1' }

Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $root 'wsl\PcSetup.Wsl.psm1') -Force

$configuration = Import-PcSetupConfiguration -Path $Config
$target = Resolve-PcSetupWslTarget -Configuration $configuration -EnvironmentName ([string]$configuration.Agent.Environment)
$distribution = [string]$target.Environment.Distribution
$linuxUser = [string]$target.Profile.LinuxUser
$realWsl = Join-Path $env:SystemRoot 'System32\wsl.exe'
if (-not (Test-Path -LiteralPath $realWsl -PathType Leaf)) { throw 'wsl.exe nao encontrado.' }

$githubConfigPath = "/home/$linuxUser/.config/gh"
& $realWsl --distribution $distribution --user $linuxUser --exec test -d $githubConfigPath
$hasGitHubConfig = $LASTEXITCODE -eq 0
if ($hasGitHubConfig) {
    & $realWsl --distribution $distribution --user $linuxUser --exec gh auth status --hostname github.com *> $null
    $hasGitHubConfig = $LASTEXITCODE -eq 0
}

if ($hasGitHubConfig) {
    Write-Host '[GITHUB] Configuracao autenticada do GitHub CLI sera montada somente para leitura no ai-jail.' -ForegroundColor Green
}
else {
    Write-Warning "GitHub CLI nao autenticado para o usuario Linux $linuxUser. O agente sera aberto sem identidade GitHub. Execute 'wsl -d $distribution -u $linuxUser' e depois 'gh auth login'."
}

$script:PcSetupRealWsl = $realWsl
$script:PcSetupGitHubConfigPath = $githubConfigPath
$script:PcSetupUseGitHubConfig = $hasGitHubConfig

function global:wsl.exe {
    $forward = @($args)
    $aiJailIndex = -1
    for ($i = 0; $i -lt $forward.Count; $i++) {
        if ([string]$forward[$i] -eq '/usr/local/bin/ai-jail') {
            $aiJailIndex = $i
            break
        }
    }

    if ($script:PcSetupUseGitHubConfig -and $aiJailIndex -ge 0 -and $forward -notcontains '--lockdown') {
        $injected = @(
            '--map', $script:PcSetupGitHubConfigPath,
            '--env', 'GIT_CONFIG_COUNT=1',
            '--env', 'GIT_CONFIG_KEY_0=credential.https://github.com.helper',
            '--env', 'GIT_CONFIG_VALUE_0=!gh auth git-credential'
        )
        $prefix = @($forward[0..$aiJailIndex])
        $suffix = @()
        if (($aiJailIndex + 1) -lt $forward.Count) {
            $suffix = @($forward[($aiJailIndex + 1)..($forward.Count - 1)])
        }
        $forward = @($prefix + $injected + $suffix)
    }

    & $script:PcSetupRealWsl @forward
}

$launcher = Join-Path $PSScriptRoot 'Start-Agent.ps1'
$invoke = @{
    Config      = $Config
    ProjectPath = $ProjectPath
    Command     = $Command
    Mode        = $Mode
}
if ($WithoutMemory) { $invoke.WithoutMemory = $true }
if ($Fresh) { $invoke.Fresh = $true }

& $launcher @invoke
