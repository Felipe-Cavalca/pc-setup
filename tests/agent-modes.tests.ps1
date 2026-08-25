#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Core.psm1') -Force

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$configuration = Import-PcSetupConfiguration -Path (Join-Path $root 'config\machine.psd1')
$launcher = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-Agent.ps1') -Raw

Assert-True ($configuration.Agent.Launcher.DefaultMode -eq 'Managed') 'O fluxo normal deve usar workstream gerenciado.'
Assert-True $configuration.Agent.Launcher.PromptForMode 'AGENTE.cmd deve explicar os modos no momento do uso.'
Assert-True $configuration.Agent.Launcher.ReviewEnabled 'O modo de revisao somente leitura deve estar disponivel.'
Assert-True ($configuration.Agent.Memory.LaunchMode -eq 'Managed') 'O ai-memory deve aceitar o launcher gerenciado.'
Assert-True ($configuration.Agent.ProjectSecrets.PreflightMode -eq 'Warn') 'O preflight de segredos deve avisar sem bloquear projetos legitimos.'
Assert-True ($launcher -match "ValidateSet\('Direct','Managed','Review'\)") 'O launcher deve restringir os modos aceitos.'
Assert-True ($launcher -match 'Get-PcSetupHarnessPackageRoot' -and $launcher -match 'lib/node_modules' -and $launcher -match '''--map'', \$harnessScopeRoot') 'O launcher deve expor somente o escopo NPM exigido pelo private-home.'
Assert-True ($launcher -match '''ai-memory'', ''run'', ''--executable'', \$harnessEntryPoint, \$Command') 'O modo gerenciado deve executar o ponto de entrada canonico do Codex por meio do ai-memory.'
Assert-True ($launcher -match 'Test-PcSetupSandboxedHarness' -and $launcher -match '''--'', \$EntryPoint, ''--version''') 'O launcher deve validar o ponto de entrada canonico dentro do ai-jail antes da sessao.'
Assert-True ($launcher -match '@\(''ai-memory'', ''run'', ''--executable'', \$harnessEntryPoint, \$Command\)') 'O modo gerenciado deve manter ai-jail fora do ai-memory e usar o executavel canonico.'
Assert-True ($launcher -match "'--lockdown', '--network', '--no-agent-state'" -and $launcher -match '''--map'', \$agentStatePath') 'A revisao deve montar somente o estado explicito do Codex em leitura.'
Assert-True ($launcher -match 'Get-PcSetupSensitiveProjectMatches') 'O launcher deve executar o preflight de segredos.'
Assert-True ($launcher -match "'--env', 'AI_MEMORY_AUTH_TOKEN'") 'O token local do ai-memory deve ser encaminhado por nome, sem entrar na configuracao.'

Write-Host 'PASS: modos simples do agente, ai-memory gerenciado e preflight de segredos.' -ForegroundColor Green
