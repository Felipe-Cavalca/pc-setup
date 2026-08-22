#requires -Version 5.1
$ErrorActionPreference = 'Stop'

foreach ($test in @('core.tests.ps1', 'restore-point.tests.ps1', 'plan.tests.ps1', 'static.tests.ps1')) {
    Write-Host "`n=== $test ===" -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot $test)
}

Write-Host "`nPASS: todos os testes." -ForegroundColor Green
