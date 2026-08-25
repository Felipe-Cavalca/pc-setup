#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Backup.psm1') -Force

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$configuration = Import-PcSetupConfiguration -Path (Join-Path $root 'config\machine.psd1')
$backupScript = Get-Content -LiteralPath (Join-Path $root 'scripts\Invoke-PcSetupBackup.ps1') -Raw
$backupModule = Get-Content -LiteralPath (Join-Path $root 'scripts\lib\PcSetup.Backup.psm1') -Raw
Assert-True (@($configuration.Backup.SourcePathKeys) -contains 'Development') 'O backup deve incluir os projetos Windows.'
Assert-True (@($configuration.Backup.UserProfileFolders) -contains 'Downloads') 'O backup deve incluir as pastas padrao do perfil Windows.'
Assert-True ($configuration.Backup.IncludeSetupInventory) 'O backup deve preservar os inventarios necessarios para reinstalar programas.'
Assert-True ($backupScript -match 'WindowsProfile/' -and $backupScript -match '\$env:USERPROFILE') 'As pastas do perfil devem ser fontes explicitas do snapshot.'
Assert-True ($backupScript -match 'SetupInventory' -and $backupScript -match 'WingetInventoryPath' -and $backupScript -match 'KnownGoodVersionPath') 'O snapshot deve incluir os inventarios Winget e known-good quando estiverem disponiveis.'
Assert-True ($backupModule -match '/XJ') 'A copia de backup nao deve seguir a juncao Data.'

$temporaryRoot = Join-Path $env:TEMP ('pc-setup-backup-test-' + [guid]::NewGuid().ToString('N'))
try {
    $snapshot = Join-Path $temporaryRoot 'backup-2026-01-01_000000'
    $sourceDirectory = Join-Path $snapshot 'Development'
    New-Item -ItemType Directory -Path $sourceDirectory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $sourceDirectory 'arquivo.txt') -Value 'conteudo de teste' -Encoding UTF8
    $files = @(Get-PcSetupBackupFileRecords -SnapshotPath $snapshot)
    Write-PcSetupJson -InputObject @{ SchemaVersion = '1.0'; Files = $files } -Path (Join-Path $snapshot 'manifest.json') | Out-Null

    $verified = Test-PcSetupBackupManifest -SnapshotPath $snapshot
    Assert-True ($verified.Valid -and $verified.Files -eq 1) 'O manifesto integro deve ser aceito.'

    Set-Content -LiteralPath (Join-Path $sourceDirectory 'arquivo.txt') -Value 'conteudo adulterado' -Encoding UTF8
    $tamperRejected = $false
    try { Test-PcSetupBackupManifest -SnapshotPath $snapshot | Out-Null }
    catch { $tamperRejected = $_.Exception.Message -match 'divergente' }
    Assert-True $tamperRejected 'Uma alteracao posterior deve ser detectada pelo hash ou tamanho.'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
}

Write-Host 'PASS: manifesto e verificacao de backup.' -ForegroundColor Green
