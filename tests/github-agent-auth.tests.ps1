#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$profile = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'wsl\profiles\agent.psd1')
$wrapper = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-AgentWithGitHub.ps1') -Raw
$rootLauncher = Get-Content -LiteralPath (Join-Path $root 'AGENTE.cmd') -Raw
$commandWrapper = Get-Content -LiteralPath (Join-Path $root 'scripts\Invoke-AgentCommand.cmd') -Raw

Assert-True (@($profile.Packages) -contains 'gh') 'O ambiente Agent deve instalar GitHub CLI.'
Assert-True ($wrapper -match '\.config/gh') 'O wrapper deve localizar somente a configuracao do GitHub CLI do usuario agent.'
Assert-True ($wrapper -match "'--map', \`$githubConfigPath") 'A configuracao do GitHub deve entrar no ai-jail somente em leitura.'
Assert-True ($wrapper -match 'GIT_CONFIG_COUNT=1') 'O Git deve receber configuracao efemera de credential helper.'
Assert-True ($wrapper -match 'credential\.https://github\.com\.helper') 'O credential helper deve ser limitado a github.com.'
Assert-True ($wrapper -match '!gh auth git-credential') 'Git HTTPS deve usar o GitHub CLI como helper.'
Assert-True ($wrapper -match "\`$forward -notcontains '--lockdown'") 'O modo Review/lockdown nao deve receber a identidade GitHub.'
Assert-True ($wrapper -notmatch 'gh auth token') 'O wrapper nao deve extrair nem copiar o token bruto do GitHub.'
Assert-True ($wrapper -match '\.GetNewClosure\(\)') 'O proxy global de wsl.exe deve capturar o contexto do wrapper em uma closure.'
Assert-True ($wrapper.Contains("Function:\global:wsl.exe")) 'O proxy deve ser publicado no escopo global para Start-Agent.ps1 encontra-lo.'
Assert-True ($wrapper -notmatch '\$script:PcSetup') 'O proxy nao pode depender do escopo de script do chamador.'
Assert-True ($wrapper -match '& \$realWsl @forward') 'O proxy deve chamar o executavel WSL real capturado pela closure.'
Assert-True ($rootLauncher -match 'Start-AgentWithGitHub\.ps1') 'AGENTE.cmd deve usar o wrapper GitHub.'
Assert-True ($commandWrapper -match 'Start-AgentWithGitHub\.ps1') 'O comando agente deve usar o wrapper GitHub.'

Write-Host 'PASS: GitHub CLI disponivel no ai-jail com proxy WSL independente do escopo do chamador.' -ForegroundColor Green
