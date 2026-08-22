#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $root 'config\machine.psd1'
$bootstrapPath = Join-Path $root 'bootstrap.ps1'
$verifyPath = Join-Path $root 'verify.ps1'
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-PcSetupExit {
    [void](Read-Host 'Pressione ENTER para fechar')
}

if (-not (Test-Administrator)) {
    try {
        $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $process = Start-Process -FilePath $windowsPowerShell -ArgumentList $arguments -Verb RunAs -Wait -PassThru
        exit $process.ExitCode
    }
    catch {
        Write-Host "Nao foi possivel obter permissao de Administrador: $($_.Exception.Message)" -ForegroundColor Red
        Wait-PcSetupExit
        exit 1
    }
}

try {
    [Console]::Title = 'pc-setup - Instalacao do Windows'
    Set-Location -LiteralPath $root

    $coreModule = Join-Path $root 'scripts\lib\PcSetup.Core.psm1'
    Import-Module $coreModule -Force
    $configuration = Import-PcSetupConfiguration -Path $configPath
    $storage = Resolve-PcSetupStorage -Configuration $configuration
    $stateDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'StateDirectory' -SystemRoot $storage.SystemRoot
    $applyStatePath = Join-Path $stateDirectory 'apply-state.json'

    Clear-Host
    Write-Host '=== pc-setup: instalacao assistida ===' -ForegroundColor Cyan
    Write-Host "Perfil: $($configuration.ProfileName)"
    Write-Host "Dados: $($storage.DataRoot)"
    Write-Host ''

    if (Test-Path -LiteralPath $applyStatePath -PathType Leaf) {
        $state = Get-Content -Raw -LiteralPath $applyStatePath | ConvertFrom-Json
        Write-Host "Retomando a instalacao na etapa: $($state.Stage)." -ForegroundColor Yellow
        & $bootstrapPath -Config $configPath -Apply
    }
    else {
        Write-Host 'Primeiro sera mostrado o plano. Nenhuma configuracao do Windows sera alterada nessa etapa.' -ForegroundColor Gray
        & $bootstrapPath -Config $configPath -Plan

        Write-Host ''
        $answer = Read-Host 'Conferiu o plano e quer iniciar a instalacao? Digite S para continuar'
        if ($answer.Trim().ToUpperInvariant() -notin @('S', 'SIM')) {
            Write-Host 'Instalacao cancelada. O plano foi mantido para consulta.' -ForegroundColor Yellow
            Wait-PcSetupExit
            exit 0
        }

        & $bootstrapPath -Config $configPath -Apply
    }

    if (Test-Path -LiteralPath $applyStatePath -PathType Leaf) {
        $state = Get-Content -Raw -LiteralPath $applyStatePath | ConvertFrom-Json
        if ($state.Stage -eq 'RestartRequired') {
            Write-Host ''
            Write-Host 'REINICIO NECESSARIO' -ForegroundColor Yellow
            Write-Host 'Reinicie o Windows e clique em INSTALAR.cmd novamente. A instalacao continuara do ponto correto.'
        }
        else {
            Write-Host "A instalacao ficou pendente na etapa $($state.Stage). Clique em INSTALAR.cmd novamente para tentar continuar." -ForegroundColor Yellow
        }
        Wait-PcSetupExit
        exit 0
    }

    Write-Host ''
    Write-Host 'Executando a verificacao final...' -ForegroundColor Cyan
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $verifyPath -Config $configPath
    $verificationExitCode = $LASTEXITCODE
    if ($verificationExitCode -eq 0) {
        Write-Host ''
        Write-Host 'INSTALACAO E VALIDACAO CONCLUIDAS.' -ForegroundColor Green
    }
    else {
        Write-Host ''
        Write-Host "A instalacao terminou, mas a validacao encontrou falhas. Codigo: $verificationExitCode" -ForegroundColor Yellow
        Write-Host 'Consulte o relatorio exibido acima.'
    }
    Wait-PcSetupExit
    exit $verificationExitCode
}
catch {
    Write-Host ''
    Write-Host 'O pc-setup foi interrompido com seguranca.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host 'Corrija o item informado e clique em INSTALAR.cmd novamente.' -ForegroundColor Yellow
    Wait-PcSetupExit
    exit 1
}
