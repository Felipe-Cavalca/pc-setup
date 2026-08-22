#requires -RunAsAdministrator
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$file = Join-Path $root 'config\packages.txt'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget nao encontrado. Atualize/instale App Installer antes de continuar.'
}

$packages = Get-Content $file | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
foreach ($id in $packages) {
    Write-Host "[WINGET] $id"
    winget install --id $id --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity
}
