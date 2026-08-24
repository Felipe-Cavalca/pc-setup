#requires -Version 5.1
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'run.ps1')

foreach ($test in @('image.tests.ps1', 'winget.tests.ps1', 'winget-context.tests.ps1', 'wsl.tests.ps1', 'agent-modes.tests.ps1', 'backup.tests.ps1', 'restore-test.tests.ps1', 'machine-audit.tests.ps1', 'version-lock.tests.ps1', 'local-accounts.tests.ps1', 'security-hardening.tests.ps1', 'update.tests.ps1', 'verify-contract.tests.ps1', 'personal-machine.tests.ps1', 'docs.tests.ps1', 'ci.tests.ps1')) {
    Write-Host "`n=== $test ===" -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot $test)
}

Write-Host "`nPASS: suite completa." -ForegroundColor Green
