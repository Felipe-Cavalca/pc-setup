#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
function Assert-Contains([string]$Content, [string]$Pattern, [string]$Message) {
    if ($Content -notmatch $Pattern) { throw $Message }
}
function Assert-NotContains([string]$Content, [string]$Pattern, [string]$Message) {
    if ($Content -match $Pattern) { throw $Message }
}

$packages = Get-Content -LiteralPath (Join-Path $root 'scripts\60-packages.ps1') -Raw
$development = Get-Content -LiteralPath (Join-Path $root 'config\packages\development.txt') -Raw
$elevatedHelper = Join-Path $root 'scripts\lib\Invoke-PcSetupWingetElevated.ps1'

Assert-Contains $packages 'winget\.exe source update --name winget --disable-interactivity' 'A fase deve atualizar explicitamente a fonte winget da conta diaria.'
Assert-NotContains $packages 'source update[^\r\n]+--accept-source-agreements' 'Source update nao aceita --accept-source-agreements nesta versao do Winget.'
Assert-Contains $packages 'winget\.exe list.+--source winget.+--accept-source-agreements' 'A consulta deve limitar a fonte e aceitar somente seus termos.'
Assert-Contains $packages 'SourceUnavailable[\s\S]+Invoke-OfflineInstaller' 'Falha ao atualizar a fonte deve chegar ao fallback offline.'
Assert-Contains $packages '-1978335207[\s\S]+RequiresAdministrator' 'O erro que exige administrador deve produzir um diagnostico proprio.'
Assert-NotContains $packages 'Invoke-WingetElevated|Start-Process.+winget' 'O Winget nao pode ser reiniciado sob outra conta.'
if (Test-Path -LiteralPath $elevatedHelper) { throw 'O auxiliar elevado mutavel deve ser removido.' }
Assert-Contains $development '(?m)^Microsoft\.PowerShell\|user\r?$' 'PowerShell deve usar o instalador do perfil diario.'

Write-Host 'PASS: fonte, contexto do usuario e fallback do Winget.' -ForegroundColor Green
