#requires -Version 5.1
[CmdletBinding()]
param([string]$Config = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path $root 'config\machine.psd1' }
$configPath = [IO.Path]::GetFullPath($Config)
$verifyPath = Join-Path $PSScriptRoot 'verify.ps1'
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Test-PcSetupAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-PcSetupExit {
    [void](Read-Host 'Pressione ENTER para fechar')
}

try {
    if (Test-PcSetupAdministrator) {
        $report = & $verifyPath -Config $configPath -PassThru
        $exitCode = if ($report.Summary.Fail -gt 0) { 1 } else { 0 }
        Wait-PcSetupExit
        exit $exitCode
    }

    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Config `"$configPath`""
    $process = Start-Process -FilePath $windowsPowerShell -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
}
catch {
    Write-Host ''
    Write-Host '[ERRO] A verificacao foi interrompida.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Wait-PcSetupExit
    exit 1
}
