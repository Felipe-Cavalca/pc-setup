#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Assert-True($Value, [string]$Message) { if (-not $Value) { throw $Message } }

$parseErrors = @()
Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psm1') } | ForEach-Object {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    $parseErrors += @($errors)
}
Assert-True ($parseErrors.Count -eq 0) "Existem erros de sintaxe: $($parseErrors.Message -join '; ')"

$config = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'config\machine.psd1')
Assert-True (-not $config.Security.ManageBitLocker) 'BitLocker deve permanecer nao gerenciado por padrao.'
Assert-True (-not $config.Debloat.Enabled) 'Debloat deve permanecer separado e desabilitado por padrao.'
Assert-True (-not $config.Accounts.God.Enabled) 'Conta God deve permanecer desabilitada por padrao.'
Assert-True (-not $config.Accounts.Public.Enabled) 'Conta Publico deve permanecer desabilitada por padrao.'

Write-Host 'PASS: sintaxe e invariantes de seguranca.' -ForegroundColor Green
