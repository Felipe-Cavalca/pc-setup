#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$errors = @()

foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psm1') })) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in @($parseErrors)) {
        $errors += "$($file.FullName):$($parseError.Extent.StartLineNumber): $($parseError.Message)"
    }
}

foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.psd1' -File)) {
    try {
        $data = Import-PowerShellDataFile -LiteralPath $file.FullName -ErrorAction Stop
        if (-not ($data -is [hashtable])) { $errors += "$($file.FullName): o PSD1 nao retorna uma hashtable." }
    }
    catch { $errors += "$($file.FullName): $($_.Exception.Message)" }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "Validacao encontrou $($errors.Count) erro(s)."
}

Write-Host 'PASS: sintaxe PowerShell e arquivos PSD1 validos.' -ForegroundColor Green
