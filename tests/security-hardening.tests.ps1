#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Core.psm1') -Force

function Assert-True([bool]$Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}

$configuration = Import-PcSetupConfiguration -Path (Join-Path $root 'config\machine.psd1')
Assert-True (-not $configuration.Agent.Capabilities.Worktree) 'Worktree deve exigir habilitacao explicita.'
Assert-True (-not $configuration.Agent.Capabilities.UpdateCheck) 'A consulta de atualizacao deve ficar no ATUALIZAR.cmd.'
Assert-True (@($configuration.Agent.ProjectSecrets.DenyPaths) -contains '.env') 'O launcher deve negar o arquivo .env.'
Assert-True (@($configuration.Agent.ProjectSecrets.DenyPaths) -contains 'secrets/**') 'O launcher deve negar o diretorio de segredos.'

$notRequested = Get-PcSetupVirtualizationAssessment -RequestedFeatures @()
Assert-True $notRequested.Ready 'Sem recurso solicitado, o preflight deve ser neutro.'

$wslWithoutFirmware = Get-PcSetupVirtualizationAssessment `
    -RequestedFeatures @('WSL','VirtualMachinePlatform') `
    -FirmwareVirtualization $false `
    -SecondLevelAddressTranslation $true `
    -VmMonitorModeExtensions $true `
    -DataExecutionPrevention $true
Assert-True (-not $wslWithoutFirmware.Ready) 'WSL 2 deve recusar virtualizacao nao exposta.'
Assert-True ((@($wslWithoutFirmware.Missing) -join ' ') -match 'firmware') 'O diagnostico deve identificar a virtualizacao ausente.'

$hyperVWithoutMonitorMode = Get-PcSetupVirtualizationAssessment `
    -RequestedFeatures @('HyperV','WindowsSandbox') `
    -FirmwareVirtualization $true `
    -SecondLevelAddressTranslation $true `
    -VmMonitorModeExtensions $false `
    -DataExecutionPrevention $true
Assert-True (-not $hyperVWithoutMonitorMode.Ready) 'Hyper-V deve exigir extensoes de monitor de VM.'

$ready = Get-PcSetupVirtualizationAssessment `
    -RequestedFeatures @('HyperV','WindowsSandbox','VirtualMachinePlatform','WSL') `
    -FirmwareVirtualization $true `
    -SecondLevelAddressTranslation $true `
    -VmMonitorModeExtensions $true `
    -DataExecutionPrevention $true
Assert-True $ready.Ready 'Uma plataforma compativel deve passar no preflight.'

$featureScript = Get-Content -LiteralPath (Join-Path $root 'scripts\10-windows-features.ps1') -Raw
$assessmentPosition = $featureScript.IndexOf('Get-PcSetupVirtualizationAssessment')
$enablePosition = $featureScript.IndexOf('Enable-WindowsOptionalFeature')
Assert-True ($assessmentPosition -ge 0 -and $enablePosition -gt $assessmentPosition) 'O preflight deve ocorrer antes da primeira alteracao de recurso.'

$agentLauncher = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-Agent.ps1') -Raw
Assert-True ($agentLauncher -match '--deny-path' -and $agentLauncher -match 'ProjectSecrets\.DenyPaths') 'O launcher deve aplicar a lista de segredos em toda execucao.'
Assert-True ($agentLauncher -match '--deny-path-except' -and $agentLauncher -match 'ProjectSecrets\.DenyPathExceptions') 'O launcher deve aceitar excecoes explicitas da configuracao.'

Write-Host 'PASS: preflight de virtualizacao e protecao do agente.' -ForegroundColor Green
