#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$config = Join-Path $root 'config\machine.psd1'
$storage = @{ SystemRoot = 'C:\'; SystemDriveLetter = 'C'; SystemDiskNumber = 0; DataRoot = 'C:\Dados'; DataMode = 'SystemDirectory'; DataVolume = $null; Inventory = @{} }

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -ne $Actual) { throw "$Message Esperado: '$Expected'. Atual: '$Actual'." }
}

$machine = & (Join-Path $root 'scripts\05-machine.ps1') -Config $config -Plan
Assert-Equal 'Plan' $machine.Mode 'Identidade da maquina deve permanecer em modo de plano.'

$directories = & (Join-Path $root 'scripts\20-directories.ps1') -Config $config -Storage $storage -Plan
Assert-Equal 'Plan' $directories.Mode 'Diretorios devem permanecer em modo de plano.'
Assert-Equal 8 @($directories.Items).Count 'O plano deve listar todos os diretorios configurados.'

$permissions = & (Join-Path $root 'scripts\40-permissions.ps1') -Config $config -Storage $storage -Plan
Assert-Equal 'Plan' $permissions.Mode 'Permissoes devem permanecer em modo de plano.'
Assert-Equal 2 @($permissions.Items).Count 'O plano deve listar as duas ACLs protegidas.'
$oneDiskPermissions = & (Join-Path $root 'scripts\40-permissions.ps1') -Config (Join-Path $root 'config\examples\machine-one-disk.psd1') -Storage $storage -Plan
Assert-Equal 2 @($oneDiskPermissions.Items).Count 'O perfil sem agente nao deve criar ACL para dados do agente.'

$packages = & (Join-Path $root 'scripts\60-packages.ps1') -Config $config -Plan
Assert-Equal 11 @($packages.Items).Count 'O plano deve listar todos os pacotes.'

$wsl = & (Join-Path $root 'scripts\70-wsl.ps1') -Config $config -Plan
Assert-Equal 'Plan' $wsl.Mode 'WSL deve permanecer em modo de plano.'

$personalization = & (Join-Path $root 'scripts\80-personalization.ps1') -Config $config -Plan
Assert-Equal $false $personalization.Enabled 'Personalizacao deve estar desabilitada no perfil padrao.'

$debloat = & (Join-Path $root 'scripts\50-debloat-akita.ps1') -Config $config -Plan
Assert-Equal $true $debloat.Enabled 'Debloat deve estar configurado no perfil Felipe.'
Assert-Equal 'RunDefaults' $debloat.Preset 'O plano deve declarar o preset revisado.'

Write-Host 'PASS: planos nao destrutivos dos componentes.' -ForegroundColor Green
