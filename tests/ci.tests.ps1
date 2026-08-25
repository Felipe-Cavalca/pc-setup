#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
function Assert-Contains([string]$Content, [string]$Pattern, [string]$Message) {
    if ($Content -notmatch $Pattern) { throw $Message }
}

$workflowPath = Join-Path $root '.github\workflows\ci.yml'
$dependabotPath = Join-Path $root '.github\dependabot.yml'
$validatorPath = Join-Path $root 'ci\validate.ps1'
$attributesPath = Join-Path $root '.gitattributes'
if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) { throw 'Workflow de CI ausente.' }
if (-not (Test-Path -LiteralPath $dependabotPath -PathType Leaf)) { throw 'Configuracao do Dependabot ausente.' }
if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) { throw 'Validador da CI ausente.' }
if (-not (Test-Path -LiteralPath $attributesPath -PathType Leaf)) { throw 'Regras de fim de linha ausentes.' }

$workflow = Get-Content -LiteralPath $workflowPath -Raw
$dependabot = Get-Content -LiteralPath $dependabotPath -Raw
$validator = Get-Content -LiteralPath $validatorPath -Raw
$attributes = Get-Content -LiteralPath $attributesPath -Raw
Assert-Contains $workflow 'shell:\s+powershell' 'A CI deve validar no Windows PowerShell 5.1.'
Assert-Contains $workflow 'PSScriptAnalyzer' 'A CI deve executar o PSScriptAnalyzer.'
Assert-Contains $workflow 'tests\\run-all\.ps1' 'A CI deve executar a suite completa.'
Assert-Contains $workflow 'actions/checkout@[0-9a-f]{40}\s+#\s+v[0-9]+\.[0-9]+\.[0-9]+' 'Actions externas devem ser fixadas por SHA completo com a versao legivel.'
if ($workflow -match 'uses:\s+[^\s]+@(v|main|master)') { throw 'A CI nao pode usar referencia mutavel de Action.' }
Assert-Contains $workflow 'bash -n wsl/linux/bootstrap\.sh' 'A CI deve validar o bootstrap Bash.'
Assert-Contains $dependabot 'package-ecosystem:\s+github-actions' 'Dependabot deve acompanhar as GitHub Actions.'
Assert-Contains $dependabot 'interval:\s+weekly' 'Atualizacoes das Actions devem ser verificadas semanalmente.'
Assert-Contains $validator 'Import-PowerShellDataFile' 'A CI deve importar e validar os arquivos PSD1.'
Assert-Contains $validator 'Parser\]::ParseFile' 'A CI deve validar a sintaxe PowerShell sem executar os scripts.'
Assert-Contains $attributes '\*\.sh text eol=lf' 'Scripts Bash devem permanecer com LF em checkouts no Windows.'

Write-Host 'PASS: contrato da integracao continua.' -ForegroundColor Green
