#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Backup.psm1') -Force

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$temporaryRoot = Join-Path $env:TEMP ('pc-setup-restore-test-' + [guid]::NewGuid().ToString('N'))
try {
    $snapshot = Join-Path $temporaryRoot 'backup-2026-01-01_000000'
    $source = Join-Path $snapshot 'PersonalData'
    New-Item -ItemType Directory -Path $source -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $source 'arquivo.txt') -Value 'conteudo restauravel' -Encoding UTF8
    $files = @(Get-PcSetupBackupFileRecords -SnapshotPath $snapshot)
    Write-PcSetupJson -InputObject @{ SchemaVersion = '1.0'; Files = $files } -Path (Join-Path $snapshot 'manifest.json') | Out-Null

    $restoreRoot = Join-Path $temporaryRoot 'destino'
    $result = Invoke-PcSetupRestoreTest -SnapshotPath $snapshot -DestinationRoot $restoreRoot -KeepRestoredCopy $false
    Assert-True ($result.Valid -and $result.Files -eq 1) 'A copia restaurada deve ser validada integralmente.'
    Assert-True $result.RemovedAfterVerification 'A copia temporaria deve ser removida depois do sucesso.'
    Assert-True (-not (Test-Path -LiteralPath $result.RestoredPath)) 'Somente a copia temporaria pode ser removida.'
    Assert-True (Test-Path -LiteralPath (Join-Path $snapshot 'manifest.json')) 'O snapshot original deve permanecer intacto.'

    $kept = Invoke-PcSetupRestoreTest -SnapshotPath $snapshot -DestinationRoot $restoreRoot -KeepRestoredCopy $true
    Assert-True (-not $kept.RemovedAfterVerification -and (Test-Path -LiteralPath $kept.RestoredPath)) 'A configuracao deve permitir manter a copia restaurada.'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
}

Write-Host 'PASS: teste real de restauracao preserva o snapshot e valida os hashes.' -ForegroundColor Green
