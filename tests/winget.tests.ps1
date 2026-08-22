#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Winget.psm1') -Force

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -ne $Actual) { throw "$Message Esperado: '$Expected'. Atual: '$Actual'." }
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Message) {
    try { & $Action; throw "NAO_LANCOU: $Message" }
    catch {
        if ($_.Exception.Message -like 'NAO_LANCOU:*' -or $_.Exception.Message -notmatch $Pattern) { throw "$Message Detalhe: $($_.Exception.Message)" }
    }
}

$export = [pscustomobject]@{
    Sources = @(
        [pscustomobject]@{
            SourceDetails = [pscustomobject]@{ Identifier = 'Microsoft.Winget.Source_8wekyb3d8bbwe' }
            Packages = @(
                [pscustomobject]@{ PackageIdentifier = 'Google.Chrome'; Version = '140.0.7339.81' },
                [pscustomobject]@{ PackageIdentifier = 'RARLab.WinRAR'; Version = '7.13.0' }
            )
        }
    )
}

$inventory = ConvertTo-PcSetupWingetInventory -ExportObject $export -PackageIds @('Google.Chrome', 'RARLab.WinRAR', 'Git.Git') -WingetVersion 'v1.12.100' -ConfigSha256 ('A' * 64) -ProjectSha256 ('B' * 64)
Assert-Equal '1.0' $inventory.SchemaVersion 'O inventario deve ter schema versionado.'
Assert-Equal 3 @($inventory.Packages).Count 'O inventario deve preservar todos os IDs solicitados.'
Assert-Equal '140.0.7339.81' ($inventory.Packages | Where-Object PackageId -eq 'Google.Chrome').Version 'A versao exportada deve ser preservada.'
Assert-Equal $false ($inventory.Packages | Where-Object PackageId -eq 'Git.Git').Found 'Pacote ausente deve ser registrado explicitamente.'
Assert-Equal 'Microsoft.Winget.Source_8wekyb3d8bbwe' ($inventory.Packages | Where-Object PackageId -eq 'RARLab.WinRAR').Source 'A fonte estruturada deve ser preservada.'

$duplicateExport = [pscustomobject]@{ Sources = @($export.Sources[0], $export.Sources[0]) }
Assert-Throws -Pattern 'mais de uma versao' -Message 'Duplicidades ambiguas devem interromper a captura.' -Action {
    ConvertTo-PcSetupWingetInventory -ExportObject $duplicateExport -PackageIds @('Google.Chrome') -WingetVersion 'v1' -ConfigSha256 ('A' * 64) -ProjectSha256 ('B' * 64) | Out-Null
}

Write-Host 'PASS: inventario estruturado do Winget.' -ForegroundColor Green
