#requires -Version 5.1
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'run.ps1')

foreach ($test in @('image.tests.ps1', 'winget.tests.ps1', 'wsl.tests.ps1', 'verify-contract.tests.ps1', 'ci.tests.ps1')) {
    Write-Host "`n=== $test ===" -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot $test)
}

Write-Host "`nPASS: suite completa." -ForegroundColor Green
