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
if ($linuxUser -notmatch '^[a-z_][a-z0-9_-]*$') { throw 'Usuario Linux do agente possui formato invalido.' }

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

# O proxy altera apenas lancamentos reais do ai-jail. A mera presenca do caminho
# /usr/local/bin/ai-jail como argumento de `test -x` nao pode receber flags do sandbox.
# GetNewClosure preserva os valores do wrapper quando Start-Agent.ps1 roda em outro escopo.
$wslProxy = {
    $forward = @($args)

    if ($hasGitHubConfig -and $forward -notcontains '--lockdown' -and $forward -notcontains '--no-network') {
        $githubArguments = @(
            '--map', $githubConfigPath,
            '--env', 'GIT_CONFIG_COUNT=1',
            '--env', 'GIT_CONFIG_KEY_0=credential.https://github.com.helper',
            '--env', 'GIT_CONFIG_VALUE_0=!gh auth git-credential'
        )

        $execIndex = -1
        for ($i = 0; $i -lt $forward.Count; $i++) {
            if ([string]$forward[$i] -eq '--exec') {
                $execIndex = $i
                break
            }
        }

        if ($execIndex -ge 0 -and ($execIndex + 1) -lt $forward.Count) {
            $execCommand = [string]$forward[$execIndex + 1]

            if ($execCommand -eq '/usr/local/bin/ai-jail') {
                $insertIndex = $execIndex + 2
                $prefix = @($forward[0..($insertIndex - 1)])
                $suffix = @()
                if ($insertIndex -lt $forward.Count) {
                    $suffix = @($forward[$insertIndex..($forward.Count - 1)])
                }
                $forward = @($prefix + $githubArguments + $suffix)
            }
            elseif ($execCommand -eq 'bash') {
                # Managed/Private iniciam o ai-jail dentro de bash -c. Injete as mesmas
                # flags no comando exec sem tocar nos demais comandos bash de preflight/finalizacao.
                $managedNeedle = 'exec /usr/local/bin/ai-jail "$@"'
                $managedReplacement = "exec /usr/local/bin/ai-jail --map '$githubConfigPath' --env 'GIT_CONFIG_COUNT=1' --env 'GIT_CONFIG_KEY_0=credential.https://github.com.helper' --env 'GIT_CONFIG_VALUE_0=!gh auth git-credential' " + '"$@"'
                for ($i = $execIndex + 2; $i -lt $forward.Count; $i++) {
                    $candidate = [string]$forward[$i]
                    if ($candidate.Contains($managedNeedle)) {
                        $forward[$i] = $candidate.Replace($managedNeedle, $managedReplacement)
                        break
                    }
                }
            }
        }
    }

    & $realWsl @forward
}.GetNewClosure()

Set-Item -Path 'Function:\global:wsl.exe' -Value $wslProxy -Force

$launcher = Join-Path $PSScriptRoot 'Start-Agent.ps1'
$invoke = @{
    Config      = $Config
    ProjectPath = $ProjectPath
    Command     = $Command
    Mode        = $Mode
}
if ($WithoutMemory) { $invoke.WithoutMemory = $true }
if ($Fresh) { $invoke.Fresh = $true }

try {
    & $launcher @invoke
}
finally {
    Remove-Item -Path 'Function:\global:wsl.exe' -Force -ErrorAction SilentlyContinue
}
