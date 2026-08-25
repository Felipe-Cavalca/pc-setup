#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
function Assert-True($Value, [string]$Message) { if (-not $Value) { throw $Message } }

$launcher = Get-Content -LiteralPath (Join-Path $root 'TESTAR-INTEGRACAO.cmd') -Raw
$integration = Get-Content -LiteralPath (Join-Path $root 'scripts\Test-PcSetupIntegration.ps1') -Raw

Assert-True ($launcher -match 'Test-PcSetupIntegration\.ps1') 'O teste integral deve ter um launcher clicavel.'
Assert-True ($integration -match 'tests\\run-all\.ps1') 'O teste integral deve executar a suite completa do projeto.'
Assert-True ($integration -match 'Start-Process[\s\S]+-Verb RunAs[\s\S]+verify\.ps1') 'Somente a verificacao do Windows deve solicitar elevacao.'
Assert-True ($integration -match 'Get-PcSetupWslEnvironments' -and $integration -match 'wsl\\verify\.ps1') 'Todos os ambientes WSL aplicaveis devem ser verificados.'
Assert-True ($integration -match 'integration-test-' -and $integration -match 'Write-PcSetupJson') 'O teste integral deve produzir um relatorio JSON proprio.'
Assert-True ($integration -notmatch 'bootstrap\.ps1|-Apply|Checkpoint-Computer|Enable-WindowsOptionalFeature') 'O teste integral deve permanecer somente leitura.'

Write-Host 'PASS: teste de integracao automatiza a auditoria sem aplicar mudancas.' -ForegroundColor Green
