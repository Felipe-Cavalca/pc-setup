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
Assert-True ($launcher -match "'--env', 'AI_MEMORY_AUTH_TOKEN'") 'O token local do ai-memory deve ser encaminhado por nome, sem entrar na configuracao.'
Assert-True ($launcher -match 'finalize-session --agent codex' -and $launcher -match '\$agentExitCode') 'A saida gerenciada deve finalizar a sessao sem ocultar o codigo do Codex.'
Assert-True ($launcher -match 'CODEX_HOME' -and $launcher -match 'uninstall --only hooks' -and $launcher -match 'uninstall --only mcp' -and $launcher -match 'pc-setup-codex-private') 'O modo privado deve usar configuracao temporaria sem hooks ou MCP do ai-memory.'
Assert-True ($rootLauncher -match 'set "agent_project=%CD%"' -and $rootLauncher -match '-ProjectPath "%agent_project%"') 'AGENTE.cmd deve encaminhar a pasta atual como projeto.'
Assert-True ($rootLauncher -notmatch '(?im)^\s*cd\s+/d\s+"%~dp0"') 'AGENTE.cmd nao deve trocar a pasta atual pela raiz do pc-setup antes de selecionar o projeto.'
Assert-True ($rootLauncher -notmatch '-Mode\s+(Managed|Direct|Review|Private)') 'AGENTE.cmd deve continuar deixando Start-Agent.ps1 apresentar a escolha interativa de modo.'
Assert-True ($commandInstaller -match 'Get-Command agente -All' -and $commandInstaller -match "SetEnvironmentVariable\('Path'" -and $commandInstaller -match 'Invoke-AgentCommand\.cmd') 'O setup deve instalar o comando agente sem sobrescrever conflitos no PATH.'
Assert-True ($commandWrapper -match 'ProjectPath "%CD%"' -and $commandWrapper -match 'Mode Managed' -and $commandWrapper -match 'Mode Private' -and $commandWrapper -match '--sem-memoria' -and $commandWrapper -match '--nova') 'O comando agente deve usar o projeto atual, Managed por padrao e expor os modos privados/novo.'

Write-Host 'PASS: modos simples do agente, pasta atual, ai-memory gerenciado e preflight de segredos.' -ForegroundColor Green
