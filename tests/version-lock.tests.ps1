#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Core.psm1') -Force

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$configuration = Import-PcSetupConfiguration -Path (Join-Path $root 'config\machine.psd1')
$latestDefinitions = @(Get-PcSetupPackageDefinitions -Configuration $configuration)
$temporaryName = 'versions.lock.test-' + [guid]::NewGuid().ToString('N') + '.json'
$temporaryPath = Join-Path (Join-Path $root 'config') $temporaryName
try {
    $packages = @($latestDefinitions | ForEach-Object { [ordered]@{ PackageId = $_.PackageId; Version = '1.2.3'; Scope = $_.Scope } })
    Write-PcSetupJson -InputObject @{ SchemaVersion = '1.0'; Packages = $packages; WSL = @() } -Path $temporaryPath | Out-Null
    $configuration.Versions.Mode = 'Locked'
    $configuration.Versions.LockFile = 'config\' + $temporaryName
    $lockedDefinitions = @(Get-PcSetupPackageDefinitions -Configuration $configuration)
    Assert-True (@($lockedDefinitions | Where-Object Version -ne '1.2.3').Count -eq 0) 'Todas as definicoes devem receber a versao fixada.'

    $lock = Get-Content -LiteralPath $temporaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $lock.Packages = @($lock.Packages | Where-Object PackageId -ne $lockedDefinitions[0].PackageId)
    Write-PcSetupJson -InputObject $lock -Path $temporaryPath | Out-Null
    $missingRejected = $false
    try { Get-PcSetupPackageDefinitions -Configuration $configuration | Out-Null }
    catch { $missingRejected = $_.Exception.Message -match 'nao possui uma versao unica' }
    Assert-True $missingRejected 'O modo Locked deve recusar pacotes sem versao.'
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
}

Write-Host 'PASS: captura e consumo do arquivo de versoes.' -ForegroundColor Green
