#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [string]$ProjectPath = '',
    [string]$Command = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path $root 'config\machine.psd1' }
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $root 'wsl\PcSetup.Wsl.psm1') -Force

function Test-SafeAgentProjectPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$ConfiguredRoots = @()
    )

    if (-not $Path.StartsWith('/') -or $Path -match "[`r`n\\]" -or $Path -match '(^|/)\.\.?(/|$)' -or $Path -match '//') { return $false }
    $normalized = $Path.TrimEnd('/')
    if ($normalized -in @('', '/', '/home', '/root', '/etc', '/usr', '/var', '/opt', '/srv', '/tmp', '/run', '/mnt')) { return $false }
    if ($normalized -match '^/home/[^/]+$') { return $false }
    if ($normalized -match '^/mnt/[a-zA-Z]$') { return $false }
    if ($normalized -match '^/mnt/[a-zA-Z]/(Users|Windows|ProgramData|Program Files|Program Files \(x86\))(/[^/]+)?$') { return $false }
    foreach ($root in $ConfiguredRoots) {
        if ($normalized -eq ([string]$root).TrimEnd('/')) { return $false }
    }
    return $true
}

try {
    $configuration = Import-PcSetupConfiguration -Path $Config
    if (-not $configuration.Agent.Enabled) { throw 'O agente esta desabilitado na configuracao.' }
    if ($configuration.Agent.Isolation -ne 'AiJail') { throw 'O launcher suporta somente Agent.Isolation = AiJail.' }

    $target = Resolve-PcSetupWslTarget -Configuration $configuration -EnvironmentName ([string]$configuration.Agent.Environment)
    $environmentDefinition = $target.Environment
    $profile = $target.Profile
    if ($env:USERNAME -ne $environmentDefinition.WindowsAccount) {
        throw "Execute o agente na conta Windows $($environmentDefinition.WindowsAccount). Usuario atual: $env:USERNAME."
    }
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe nao encontrado.' }
    if (@(Get-PcSetupWslDistributionNames) -notcontains $environmentDefinition.Distribution) {
        throw "Distribuicao ausente. Execute .\wsl\bootstrap.ps1 -Environment $($environmentDefinition.Name) -Apply."
    }

    if ([string]::IsNullOrWhiteSpace($Command)) { $Command = [string]$configuration.Agent.DefaultCommand }
    if ($Command -notmatch '^[A-Za-z0-9._-]+$') { throw 'O comando do agente deve ser somente o nome de um executavel.' }
    if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
        $ProjectPath = [string]$configuration.Agent.Workspace.DefaultPath
    }
    if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
        $ProjectPath = Read-Host 'Caminho completo do projeto que sera liberado (Windows ou Linux no WSL)'
    }
    if ([string]::IsNullOrWhiteSpace($ProjectPath) -or $ProjectPath -match "[`r`n]") { throw 'Caminho de projeto invalido.' }

    $distribution = [string]$environmentDefinition.Distribution
    if ($ProjectPath.StartsWith('/')) {
        $wslProjectPath = $ProjectPath
    }
    else {
        $resolvedProject = Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $resolvedProject.Path -PathType Container)) { throw 'O projeto deve ser um diretorio existente.' }
        $wslProjectPath = ConvertTo-PcSetupWslPath -Distribution $distribution -WindowsPath $resolvedProject.Path
    }
    if ($configuration.Agent.Workspace.Mode -ne 'SelectedProjectOnly') { throw 'Politica de workspace do agente nao suportada.' }

    & wsl.exe --distribution $distribution --user ([string]$profile.LinuxUser) -- test -d $wslProjectPath
    if ($LASTEXITCODE -ne 0) { throw "Diretorio nao encontrado dentro do WSL: $wslProjectPath" }
    $canonicalOutput = @(& wsl.exe --distribution $distribution --user ([string]$profile.LinuxUser) -- readlink --canonicalize-existing -- $wslProjectPath 2>$null)
    if ($LASTEXITCODE -ne 0 -or $canonicalOutput.Count -eq 0) { throw "Nao foi possivel canonicalizar o workspace: $wslProjectPath" }
    $wslProjectPath = ([string]$canonicalOutput[-1]).Replace([char]0, '').Trim()
    $configuredRoots = @(
        Get-PcSetupWslEnvironments -Configuration $configuration |
            Where-Object { $_.Enabled -and $_.WindowsAccount -eq $environmentDefinition.WindowsAccount -and $_.Distribution -eq $distribution } |
            ForEach-Object { (Import-PcSetupWslProfile -Configuration $configuration -Environment $_).ProjectRoot }
    )
    if (-not (Test-SafeAgentProjectPath -Path $wslProjectPath -ConfiguredRoots $configuredRoots)) { throw "O launcher recusa uma raiz ampla ou nao canonica como workspace: $wslProjectPath" }
    & wsl.exe --distribution $distribution --user ([string]$profile.LinuxUser) -- test -x /usr/local/bin/ai-jail
    if ($LASTEXITCODE -ne 0) { throw 'ai-jail ausente. Aplique e valide o ambiente WSL Agent.' }
    & wsl.exe --distribution $distribution --user ([string]$profile.LinuxUser) -- bash -lc "command -v -- '$Command' >/dev/null"
    if ($LASTEXITCODE -ne 0) { throw "Agente '$Command' nao instalado para o usuario Linux $($profile.LinuxUser)." }

    if ($profile.ContainsKey('AiMemory') -and $profile.AiMemory.Enabled) {
        $memoryService = 'pc-setup-ai-memory-' + $environmentDefinition.Name.ToLowerInvariant() + '.service'
        & wsl.exe --distribution $distribution --user root -- systemctl start $memoryService
        if ($LASTEXITCODE -ne 0) { throw "Nao foi possivel iniciar o servico do ai-memory: $memoryService. Execute ATUALIZAR.cmd e consulte o relatorio WSL." }
        $memoryServerUrl = [string]$profile.AiMemory.ServerUrl
        & wsl.exe --distribution $distribution --user ([string]$profile.LinuxUser) -- env "AI_MEMORY_SERVER_URL=$memoryServerUrl" bash -c 'set -a; . "$HOME/.config/ai-memory/env"; set +a; /usr/local/bin/ai-memory status --json >/dev/null'
        if ($LASTEXITCODE -ne 0) { throw "ai-memory nao respondeu em $memoryServerUrl. Execute ATUALIZAR.cmd e consulte o relatorio WSL." }
    }

    $capabilities = $configuration.Agent.Capabilities
    $aiJailArguments = @(
        if ($capabilities.Network) { '--network' } else { '--no-network' }
        if ($capabilities.PersistAgentState) { '--agent-state' } else { '--no-agent-state' }
        if ($capabilities.Docker) { '--docker' } else { '--no-docker' }
        if ($capabilities.SSH) { '--ssh' } else { '--no-ssh' }
        if ($capabilities.Display) { '--display' } else { '--no-display' }
        if ($capabilities.GPU) { '--gpu' } else { '--no-gpu' }
        if ($capabilities.X11) { '--x11' } else { '--no-x11' }
        if ($capabilities.HostSharedMemory) { '--host-shm' } else { '--no-host-shm' }
        if ($capabilities.TerminalPassthrough) { '--terminal-passthrough' } else { '--no-terminal-passthrough' }
        if ($capabilities.InheritEnvironment) { '--inherit-env' } else { '--no-inherit-env' }
        if ($capabilities.UpdateCheck) { '--update-check' } else { '--no-update-check' }
        if ($capabilities.Worktree) { '--worktree' } else { '--no-worktree' }
        if ($capabilities.SystemdUser) { '--systemd-user' } else { '--no-systemd-user' }
        if ($capabilities.Tailscale) { '--tailscale' } else { '--no-tailscale' }
        if ($capabilities.Pictures) { '--pictures' } else { '--no-pictures' }
    )
    foreach ($denyPath in @($configuration.Agent.ProjectSecrets.DenyPaths)) {
        $aiJailArguments += @('--deny-path', [string]$denyPath)
    }
    foreach ($exception in @($configuration.Agent.ProjectSecrets.DenyPathExceptions)) {
        $aiJailArguments += @('--deny-path-except', [string]$exception)
    }
    if ($profile.ContainsKey('AiMemory') -and $profile.AiMemory.Enabled) {
        $aiJailArguments += @('--rw-map', "/home/$($profile.LinuxUser)/.local/share/ai-memory")
    }
    $aiJailArguments += @(
        '--private-home'
        '--landlock'
        '--seccomp'
        '--rlimits'
        '--no-save-config'
        '--no-mise'
        '--'
        $Command
    )

    Write-Host "[AGENTE] $Command em $wslProjectPath via ai-jail." -ForegroundColor Cyan
    & wsl.exe --distribution $distribution --user ([string]$profile.LinuxUser) --cd $wslProjectPath -- /usr/local/bin/ai-jail @aiJailArguments
    exit $LASTEXITCODE
}
catch {
    Write-Host "[ERRO] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
