#requires -RunAsAdministrator
[CmdletBinding()]
param([switch]$ForceUnsupported)

$ErrorActionPreference = 'Stop'
$repo = 'LeDragoX/Win-Debloat-Tools'
$commit = '4766a980ce25a5d130f7c8e801550afab876cd34'
$displayVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion
$supported = @('21H2','22H2','23H2','24H2')

Write-Host "Windows: $displayVersion"
Write-Host "Debloat: $repo@$commit"

if (($displayVersion -notin $supported) -and (-not $ForceUnsupported)) {
    throw "O Win-Debloat-Tools arquivado declara suporte ate 24H2. Versao atual: $displayVersion. Abortado. Leia docs/DEBLOAT.md."
}

$work = Join-Path $env:TEMP "pc-setup-debloat-$commit"
$zip = "$work.zip"
$url = "https://github.com/$repo/archive/$commit.zip"

Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zip -Force -ErrorAction SilentlyContinue

Write-Host '[DOWNLOAD] Baixando commit imutavel do LeDragoX...'
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
Expand-Archive -Path $zip -DestinationPath $work -Force

$script = Get-ChildItem $work -Recurse -Filter 'WinDebloatTools.ps1' | Select-Object -First 1
if (-not $script) { throw 'WinDebloatTools.ps1 nao encontrado no pacote baixado.' }

Get-ChildItem $script.Directory.FullName -Recurse -File | Unblock-File

Write-Warning 'Este script fara alteracoes de sistema. O projeto de origem esta arquivado. Revise docs/DEBLOAT.md.'
Write-Host '[RUN] Iniciando modo CLI do Win-Debloat-Tools...'
Push-Location $script.Directory.FullName
try { & $script.FullName 'CLI' }
finally { Pop-Location }
