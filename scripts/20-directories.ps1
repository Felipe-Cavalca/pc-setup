#requires -RunAsAdministrator
if (-not (Test-Path 'D:\')) { throw 'Disco D: nao encontrado. Corrija isso antes de continuar.' }

$paths = @(
    'D:\Apps',
    'D:\Games',
    'D:\Dev',
    'D:\Data\Felipe',
    'D:\Shared',
    'D:\Downloads',
    'D:\VMs',
    'D:\Containers',
    'D:\Agent\Codex'
)

foreach ($path in $paths) {
    if (Test-Path $path) { Write-Host "[OK] $path"; continue }
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Write-Host "[CREATE] $path"
}
