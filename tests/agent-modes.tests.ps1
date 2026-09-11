#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Core.psm1') -Force

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$configuration = Import-PcSetupConfiguration -Path (Join-Path $root 'config\machine.psd1')
$launcher = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-Agent.ps1') -Raw
$rootLauncher = Get-Content -LiteralPath (Join-Path $root 'AGENTE.cmd') -Raw
$commandInstaller = Get-Content -LiteralPath (Join-Path $root 'scripts\Install-AgentCommand.ps1') -Raw
$commandWrapper = Get-Content -LiteralPath (Join-Path $root 'scripts\Invoke-AgentCommand.cmd') -Raw

Assert-True ($configuration.Agent.Launcher.DefaultMode -eq 'Managed') 'O fluxo normal deve usar workstream gerenciado.'
Assert-True $configuration.Agent.Launcher.PromptForMode 'AGENTE.cmd deve explicar os modos no momento do uso.'
Assert-True $configuration.Agent.Launcher.ReviewEnabled 'O modo de revisao somente leitura deve estar disponivel.'
Assert-True ($configuration.Agent.Memory.LaunchMode -eq 'Managed') 'O ai-memory deve aceitar o launcher gerenciado.'
Assert-True ($configuration.Agent.ProjectSecrets.PreflightMode -eq 'Warn') 'O preflight de segredos deve avisar sem bloquear projetos legitimos.'
Assert-True ($launcher -match "ValidateSet\('Direct','Managed','Review','Private'\)") 'O launcher deve restringir os modos aceitos e oferecer uma sessao privada.'
Assert-True ($launcher -match 'Get-PcSetupHarnessPackageRoot' -and $launcher -match 'lib/node_modules' -and $launcher -match '''--map'', \$harnessScopeRoot') 'O launcher deve expor somente o escopo NPM exigido pelo private-home.'
Assert-True ($launcher -match '''ai-memory'', ''run''' -and $launcher -match '''--executable'', \$harnessEntryPoint, \$Command') 'O modo gerenciado deve executar o ponto de entrada canonico do Codex por meio do ai-memory.'
Assert-True ($launcher -match 'Test-PcSetupSandboxedHarness' -and $launcher -match '''--'', \$EntryPoint, ''--version''') 'O launcher deve validar o ponto de entrada canonico dentro do ai-jail antes da sessao.'
Assert-True ($launcher -match '@\(''ai-memory'', ''run''\)' -and $launcher -match '\$Fresh' -and $launcher -match '''--fresh''') 'O modo gerenciado deve retomar por padrao e permitir uma sessao nova explicita.'
Assert-True ($launcher -match "'--lockdown', '--network', '--no-agent-state'" -and $launcher -match '''--map'', \$agentStatePath') 'A revisao deve montar somente o estado explicito do Codex em leitura.'
Assert-True ($launcher -match 'Get-PcSetupSensitiveProjectMatches') 'O launcher deve executar o preflight de segredos.'
Assert-True ($launcher.Contains('root="$1"') -and $launcher.Contains('cd -- "$root" || exit 2') -and $launcher.Contains('compgen -G "$pattern"')) 'O preflight deve tratar a raiz como caminho literal e aplicar glob somente aos padroes configurados.'
Assert-True (-not $launcher.Contains('compgen -G "$root/$pattern"')) 'A raiz do projeto nao pode ser interpretada como glob.'
Assert-True ($launcher.Contains('literal_prefix="${pattern%%[*?[]*}"') -and $launcher.Contains('[[ -r "$current" && -x "$current" ]] || exit 3')) 'O preflight deve sinalizar diretórios literais sensíveis que não podem ser inspecionados.'
Assert-True ($launcher -notmatch 'find \"\$root\"') 'O preflight nao deve percorrer a arvore inteira do projeto com find.'
Assert-True ($launcher -match '\$preflightMode\s*=\s*\[string\]\$configuration\.Agent\.ProjectSecrets\.PreflightMode') 'O comportamento de falha do preflight deve respeitar o modo configurado.'
Assert-True ($launcher -match "if \(\`$preflightMode -eq 'Stop'\) \{ throw \}") 'O modo Stop deve continuar bloqueando quando a inspecao falhar.'
Assert-True ($launcher -match 'Write-Warning .*regras --deny-path do ai-jail continuam ativas') 'O modo Warn deve continuar a sessao informando que deny-path permanece ativo.'
Assert-True ($launcher.Contains("bash -c `$matchScript 'pc-setup' `$ProjectPath @Patterns")) 'O preflight deve reservar argv[0] antes do caminho do projeto.'
Assert-True ($launcher.Contains("bash -c `$preparePrivateHome 'pc-setup' `$privateCodexHome")) 'A preparacao privada deve reservar argv[0] antes do estado temporario.'
Assert-True ($launcher.Contains("bash -c `$launchScript 'pc-setup' `$memoryServerUrl @aiJailArguments")) 'O launcher gerenciado deve reservar argv[0] antes da URL do ai-memory.'
Assert-True ($launcher.Contains("bash -c `$privateLaunchScript 'pc-setup' `$privateCodexHome @aiJailArguments")) 'O launcher privado deve reservar argv[0] antes do CODEX_HOME.'
Assert-True ($launcher.Contains("bash -c `$finalizeScript 'pc-setup' `$memoryServerUrl `$wslProjectPath")) 'A finalizacao deve reservar argv[0] antes dos argumentos do ai-memory.'
Assert-True (-not $launcher.Contains('bash -c $matchScript -- $ProjectPath')) 'O launcher nao pode depender de -- como argv[0] atraves do wsl.exe.'
Assert-True ($launcher -match "'--env', 'AI_MEMORY_AUTH_TOKEN'") 'O token local do ai-memory deve ser encaminhado por nome, sem entrar na configuracao.'
Assert-True ($launcher -match 'finalize-session --agent codex' -and $launcher -match '\$agentExitCode') 'A saida gerenciada deve finalizar a sessao sem ocultar o codigo do Codex.'
Assert-True ($launcher -match 'CODEX_HOME' -and $launcher -match 'uninstall --only hooks' -and $launcher -match 'uninstall --only mcp' -and $launcher -match 'pc-setup-codex-private') 'O modo privado deve usar configuracao temporaria sem hooks ou MCP do ai-memory.'
Assert-True ($rootLauncher -match 'set "agent_project=%CD%"' -and $rootLauncher -match '-ProjectPath "%agent_project%"') 'AGENTE.cmd deve encaminhar a pasta atual como projeto.'
Assert-True ($rootLauncher -notmatch '(?im)^\s*cd\s+/d\s+"%~dp0"') 'AGENTE.cmd nao deve trocar a pasta atual pela raiz do pc-setup antes de selecionar o projeto.'
Assert-True ($rootLauncher -notmatch '-Mode\s+(Managed|Direct|Review|Private)') 'AGENTE.cmd deve continuar deixando Start-Agent.ps1 apresentar a escolha interativa de modo.'
Assert-True ($commandInstaller -match 'Get-Command agente -All' -and $commandInstaller -match "SetEnvironmentVariable\('Path'" -and $commandInstaller -match 'Invoke-AgentCommand\.cmd') 'O setup deve instalar o comando agente sem sobrescrever conflitos no PATH.'
Assert-True ($commandWrapper -match 'ProjectPath "%CD%"' -and $commandWrapper -match 'Mode Managed' -and $commandWrapper -match 'Mode Private' -and $commandWrapper -match '--sem-memoria' -and $commandWrapper -match '--nova') 'O comando agente deve usar o projeto atual, Managed por padrao e expor os modos privados/novo.'

Write-Host 'PASS: modos simples do agente, argv preservado no WSL, ai-memory gerenciado e preflight de segredos.' -ForegroundColor Green
