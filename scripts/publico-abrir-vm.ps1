#requires -Version 5.1
[CmdletBinding()]
param([string]$Config = '')

if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\machine.psd1' }
$coreModule = Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1'
Import-Module $coreModule -Force
$configuration = Import-PcSetupConfiguration -Path $Config
if (-not $configuration.Accounts.Public.Enabled -or -not $configuration.Features.PublicVirtualMachine) {
    throw 'A conta/VM publica esta desabilitada na configuracao. Nenhuma VM foi aberta.'
}

$vmName = [string]$configuration.Accounts.Public.VirtualMachineName
if ([string]::IsNullOrWhiteSpace($vmName)) { throw 'Accounts.Public.VirtualMachineName nao pode ficar vazio.' }
$vmConnect = Join-Path $env:WINDIR 'System32\vmconnect.exe'
if (-not (Test-Path -LiteralPath $vmConnect -PathType Leaf)) { throw 'VMConnect nao encontrado. Confirme que o Hyper-V esta instalado.' }
Start-Process -FilePath $vmConnect -ArgumentList @('localhost', $vmName)
