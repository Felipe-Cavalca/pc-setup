#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [string]$ProjectPath = '',
    [string]$Command = '',
    [ValidateSet('Direct','Managed','Review')]
    [string]$Mode = ''
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

function Select-PcSetupAgentMode {
    param([Parameter(Mandatory)][hashtable]$AgentConfiguration)

    $defaultMode = [string]$AgentConfiguration.Launcher.DefaultMode
    if (-not $AgentConfiguration.Launcher.PromptForMode) { return $defaultMode }

    Write-Host 'Modo do agente:' -ForegroundColor Cyan
    Write-Host "  1. Normal ($defaultMode, recomendado) - projeto gravavel, online e isolado"
    if ($AgentConfiguration.Launcher.ReviewEnabled) {
        Write-Host '  2. Revisao - projeto somente leitura; continua online para o Codex'
    }
    Write-Host '  3. Direto - compatibilidade com o fluxo anterior, mantendo hooks do ai-memory'
    $selection = Read-Host 'Escolha 1, 2 ou 3; Enter usa 1'
    if ([string]::IsNullOrWhiteSpace($selection) -or $selection -eq '1') { return $defaultMode }
    if ($selection -eq '2' -and $AgentConfiguration.Launcher.ReviewEnabled) { return 'Review' }
    if ($selection -eq '3') { return 'Direct' }
    throw 'Modo invalido. Use 1, 2 ou 3.'
}

function Get-PcSetupSensitiveProjectMatches {
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$LinuxUser,
        [Parameter(Mandatory)][string]$ProjectPath,
        [string[]]$Patterns = @()
    )

    if ($Patterns.Count -eq 0) { return @() }
    $findScript = 'root="$1"; shift; for pattern in "$@"; do find "$root" -path "$root/.git" -prune -o -path "$root/node_modules" -prune -o -path "$root/vendor" -prune -o -path "$root/$pattern" -print -quit 2>/dev/null; done'
    $output = @(& wsl.exe --distribution $Distribution --user $LinuxUser --exec bash -c $findScript -- $ProjectPath @Patterns)
    if ($LASTEXITCODE -ne 0) { throw 'O preflight de segredos nao conseguiu inspecionar o projeto.' }
    return @($output | ForEach-Object { ([string]$_).Replace([string][char]0, [string]::Empty).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
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
        throw "Distribuicao ausente. Execute ATUALIZAR.cmd na raiz antes de abrir o agente."
    }

    if ([string]::IsNullOrWhiteSpace($Command)) { $Command = [string]$configuration.Agent.DefaultCommand }
    if ($Command -notmatch '^[A-Za-z0-9._-]+$') { throw 'O comando do agente deve ser somente o nome de um executavel.' }
    if ([string]::IsNullOrWhiteSpace($Mode)) { $Mode = Select-PcSetupAgentMode -AgentConfiguration $configuration.Agent }
    if ($Mode -eq 'Review' -and -not $configuration.Agent.Launcher.ReviewEnabled) { throw 'O modo Review esta desabilitado na configuracao.' }
    if ($Mode -eq 'Managed' -and (-not $configuration.Agent.Memory.Enabled -or [string]$configuration.Agent.Memory.LaunchMode -ne 'Managed')) { throw 'O modo Managed exige Agent.Memory habilitado e configurado para Managed.' }
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

    & wsl.exe --distribution $distribution --user ([string]$profile.LinuxUser) --exec test -d $wslProjectPath
    if ($LASTEXITCODE -ne 0) { throw "Diretorio nao encontrado dentro do WSL: $wslProjectPath" }
    $canonicalOutput = @(& wsl.exe --distribution $distribution --user ([string]$profile.LinuxUser) --exec readlink --canonicalize-existing -- $wslProjectPath 2>$null)
    if ($LASTEXITCODE -ne 0 -or $canonicalOutput.Count -eq 0) { throw "Nao foi possivel canonicalizar o workspace: $wslProjectPath" }
    $wslProjectPath = ([string]$canonicalOutput[-1]).Replace([string][char]0, [string]::Empty).Trim()
    $configuredRoots = @(
        Get-PcSetupWslEnvironments -Configuration $configuration |
            Where-Object { $_.Enabled -and $_.WindowsAccount -eq $environmentDefinition.WindowsAccount -and $_.Distribution -eq $distribution } |
            ForEach-Object { (Import-PcSetupWslProfile -Configuration $configuration -Environment $_).ProjectRoot }
    )
    if (-not (Test-SafeAgentProjectPath -Path $wslProjectPath -ConfiguredRoots $configuredRoots)) { throw "O launcher recusa uma raiz ampla ou nao canonica como workspace: $wslProjectPath" }
    & wsl.exe --distribution $distribution --user ([string]$profile.LinuxUser) --exec test -x /usr/local/bin/ai-jail
    if ($LASTEXITCODE -ne 0) { throw 'ai-jail ausente. Aplique e valide o ambiente WSL Agent.' }
    & wsl.exe --distribution $distribution --user ([string]$profile.LinuxUser) --exec bash -lc "command -v -- '$Command' >/dev/null"
    if ($LASTEXITCODE -ne 0) { throw "Agente '$Command' nao instalado para o usuario Linux $($profile.LinuxUser)." }
    if ($Mode -eq 'Managed') {
        & wsl.exe --distribution $distribution --user ([string]$profile.LinuxUser) --exec test -x /usr/local/bin/ai-memory
        if ($LASTEXITCODE -ne 0) { throw 'ai-memory ausente. Execute ATUALIZAR.cmd e tente novamente.' }
    }

    if ([string]$configuration.Agent.ProjectSecrets.PreflightMode -ne 'Off') {
        $sensitiveMatches = @(Get-PcSetupSensitiveProjectMatches -Distribution $distribution -LinuxUser ([string]$profile.LinuxUser) -ProjectPath $wslProjectPath -Patterns @($configuration.Agent.ProjectSecrets.DenyPaths))
        if ($sensitiveMatches.Count -gt 0) {
            $relativeMatches = @($sensitiveMatches | ForEach-Object { $_.Substring($wslProjectPath.TrimEnd('/').Length).TrimStart('/') })
            Write-Host "[SEGREDOS] $($relativeMatches.Count) caminho(s) protegido(s) encontrado(s): $($relativeMatches -join ', ')" -ForegroundColor Yellow
            Write-Host 'Eles serao negados pelo ai-jail. Arquivos secretos criados depois da abertura exigem uma nova sessao para receber a regra.' -ForegroundColor Yellow
            if ([string]$configuration.Agent.ProjectSecrets.PreflightMode -eq 'Stop') { throw 'O preflight encontrou caminhos sensiveis e a politica esta configurada como Stop.' }
        }
    }

    $strictLockdown = $Mode -eq 'Review' -or ($configuration.Agent.RestrictedMode.Enabled -and $configuration.Agent.RestrictedMode.Lockdown)
    if (-not $strictLockdown -and $profile.ContainsKey('AiMemory') -and $profile.AiMemory.Enabled) {
        $memoryService = 'pc-setup-ai-memory-' + $environmentDefinition.Name.ToLowerInvariant() + '.service'
        & wsl.exe --distribution $distribution --user root --exec systemctl start $memoryService
        if ($LASTEXITCODE -ne 0) { throw "Nao foi possivel iniciar o servico do ai-memory: $memoryService. Execute ATUALIZAR.cmd e consulte o relatorio WSL." }
        $memoryServerUrl = [string]$profile.AiMemory.ServerUrl
        & wsl.exe --distribution $distribution --user ([string]$profile.LinuxUser) --exec env "AI_MEMORY_SERVER_URL=$memoryServerUrl" bash -c 'set -a; . "$HOME/.config/ai-memory/env"; set +a; /usr/local/bin/ai-memory status --json >/dev/null'
        if ($LASTEXITCODE -ne 0) { throw "ai-memory nao respondeu em $memoryServerUrl. Execute ATUALIZAR.cmd e consulte o relatorio WSL." }
    }

    $capabilities = $configuration.Agent.Capabilities
    if ($strictLockdown) {
        $aiJailArguments = @('--lockdown', '--network', '--agent-state', '--no-inherit-env', '--no-save-config', '--no-worktree')
    }
    else {
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
        )
    }

    foreach ($denyPath in @($configuration.Agent.ProjectSecrets.DenyPaths)) {
        $aiJailArguments += @('--deny-path', [string]$denyPath)
    }
    foreach ($exception in @($configuration.Agent.ProjectSecrets.DenyPathExceptions)) {
        $aiJailArguments += @('--deny-path-except', [string]$exception)
    }
    foreach ($environmentVariable in @($configuration.Agent.EnvironmentAllowList)) {
        $aiJailArguments += @('--env', [string]$environmentVariable)
    }
    if (-not $strictLockdown -and $profile.ContainsKey('AiMemory') -and $profile.AiMemory.Enabled) {
        $aiJailArguments += @('--env', 'AI_MEMORY_AUTH_TOKEN', '--env', 'AI_MEMORY_SERVER_URL')
    }

    $sandboxCommand = if ($Mode -eq 'Managed' -and -not $strictLockdown) { @('ai-memory', 'run', $Command) } else { @($Command) }
    $aiJailArguments += @('--') + $sandboxCommand

    $isolationLabel = if ($strictLockdown) { 'revisao somente leitura; online para autenticacao do Codex' } elseif ($Mode -eq 'Managed') { 'ai-jail restrito com workstream gerenciado pelo ai-memory' } else { 'ai-jail restrito com hooks do ai-memory' }
    Write-Host "[AGENTE] $Command em $wslProjectPath via $isolationLabel." -ForegroundColor Cyan
    if (-not $strictLockdown -and $profile.ContainsKey('AiMemory') -and $profile.AiMemory.Enabled) {
        $memoryServerUrl = [string]$profile.AiMemory.ServerUrl
        $launchScript = 'set -a; . "$HOME/.config/ai-memory/env"; set +a; export AI_MEMORY_SERVER_URL="$1"; shift; exec /usr/local/bin/ai-jail "$@"'
        & wsl.exe --distribution $distribution --user ([string]$profile.LinuxUser) --cd $wslProjectPath --exec bash -c $launchScript -- $memoryServerUrl @aiJailArguments
    }
    else {
        & wsl.exe --distribution $distribution --user ([string]$profile.LinuxUser) --cd $wslProjectPath --exec /usr/local/bin/ai-jail @aiJailArguments
    }
    exit $LASTEXITCODE
}
catch {
    Write-Host "[ERRO] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
