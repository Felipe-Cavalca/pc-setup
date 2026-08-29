#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Assert-True($Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}

$system = Get-Content -LiteralPath (Join-Path $root 'scripts\Invoke-PcSetupSystemPersonalization.ps1') -Raw
$machine = Get-Content -LiteralPath (Join-Path $root 'scripts\82-personalization-machine.ps1') -Raw
$user = Get-Content -LiteralPath (Join-Path $root 'scripts\80-personalization.ps1') -Raw

Assert-True ($system -match "TaskbarStatus\s*=\s*'ManualRequired'" -and $system -match 'TaskbarError\s*=\s*\$taskbarError') 'A recusa do CSP deve ser registrada sem falhar a etapa LocalSystem.'
Assert-True ($machine -match "TaskbarStatus -eq 'ManualRequired'" -and $machine -match 'a instalacao continuara') 'A fase administrativa deve avisar sobre o fallback manual.'
Assert-True ($user -match "personalization-system-\*\.json" -and $user -match '\[MANUAL\].+barra') 'A conta diaria deve mostrar o aviso persistido pela fase administrativa.'

Write-Host 'PASS: recusa do CSP da barra usa fallback manual sem interromper a personalizacao.' -ForegroundColor Green
