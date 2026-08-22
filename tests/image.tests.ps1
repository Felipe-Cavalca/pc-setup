#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Assert-True($Value, [string]$Message) {
    if (-not $Value) {
        throw $Message
    }
}

$mediaDirectory = Join-Path $root 'imagem-windows\midia'
$answerFile = Join-Path $mediaDirectory 'autounattend.pt-BR.opcional.xml'
$validator = Join-Path $mediaDirectory 'Validar-Midia.ps1'
$launcher = Join-Path $mediaDirectory 'Validar-Midia.cmd'

[xml]$answerXml = Get-Content -LiteralPath $answerFile -Raw -Encoding UTF8
Assert-True ($answerXml.DocumentElement.LocalName -eq 'unattend') 'O arquivo opcional deve ter raiz unattend.'
Assert-True ($answerXml.DocumentElement.NamespaceURI -eq 'urn:schemas-microsoft-com:unattend') 'O arquivo opcional deve usar o namespace oficial.'

foreach ($nodeName in @('DiskConfiguration', 'ImageInstall', 'UserAccounts', 'AutoLogon', 'Password', 'ProductKey', 'RunSynchronous', 'RunAsynchronous', 'FirstLogonCommands', 'Extensions')) {
    $count = @($answerXml.SelectNodes("//*[local-name()='$nodeName']")).Count
    Assert-True ($count -eq 0) "O arquivo opcional nao pode conter $nodeName."
}

$allowedComponents = @('Microsoft-Windows-International-Core-WinPE', 'Microsoft-Windows-International-Core')
$components = @($answerXml.SelectNodes("//*[local-name()='component']") | ForEach-Object { $_.GetAttribute('name') })
Assert-True (@($components | Where-Object { $_ -notin $allowedComponents }).Count -eq 0) 'O arquivo opcional deve conter somente componentes de idioma.'

$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($validator, [ref]$tokens, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) "O validador da midia tem erro de sintaxe: $($parseErrors.Message -join '; ')"

$launcherContent = Get-Content -LiteralPath $launcher -Raw
Assert-True ($launcherContent -match 'Validar-Midia\.ps1') 'O launcher da midia deve chamar o validador PowerShell.'

Write-Host 'PASS: midia e autounattend opcional mantem as escolhas e nao executam pos-instalacao.' -ForegroundColor Green
