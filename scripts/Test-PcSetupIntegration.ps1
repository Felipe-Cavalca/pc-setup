#requires -Version 5.1
[CmdletBinding()]
param([string]$Config = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path $root 'config\machine.psd1' }
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$testSuitePath = Join-Path $root 'tests\run-all.ps1'
$verifyPath = Join-Path $root 'scripts\verify.ps1'
$wslVerifyPath = Join-Path $root 'wsl\verify.ps1'

Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.ExecutionLog.psm1') -Force
$configuration = Import-PcSetupConfiguration -Path $Config
$userReportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'UserReportDirectory'
$systemRoot = [IO.Path]::GetPathRoot($env:SystemRoot)
$machineReportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'ReportDirectory' -SystemRoot $systemRoot
$reportPath = Join-Path $userReportDirectory ('integration-test-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
$machineVerifyReportPath = Join-Path $machineReportDirectory ('integration-verify-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
$executionLog = if ($configuration.Runtime.ExecutionLogEnabled) { New-PcSetupExecutionLog -Directory $userReportDirectory -Operation 'TesteIntegracao' } else { $null }
$currentStage = 'Inicializacao'
$steps = @()
$failure = $null

function Add-PcSetupIntegrationStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('PASS','FAIL')][string]$Status,
        [Parameter(Mandatory)][string]$Detail
    )
    $script:steps += [pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail }
}

function Write-PcSetupIntegrationEvent {
    param(
        [Parameter(Mandatory)][ValidateSet('Started','Info','Pending','Succeeded','Failed')][string]$Status,
        [Parameter(Mandatory)][string]$Message,
        [string]$Command = '',
        [object[]]$Arguments = @()
    )
    if ($null -ne $script:executionLog) {
        Write-PcSetupExecutionEvent -Log $script:executionLog -Stage $script:currentStage -Status $Status -Message $Message -Command $Command -Arguments $Arguments | Out-Null
    }
}

try {
    if ($env:USERNAME -ne [string]$configuration.Accounts.DailyUser.Name) {
        throw "Execute o teste na conta diaria $($configuration.Accounts.DailyUser.Name). Usuario atual: $env:USERNAME."
    }

    Write-Host '=== pc-setup: teste de integracao ===' -ForegroundColor Cyan
    Write-Host 'O teste nao aplica configuracoes. O UAC sera solicitado somente para validar o estado do Windows.'
    if ($null -ne $executionLog) { Write-Host "[LOG] $($executionLog.Path)" -ForegroundColor DarkGray }
    Write-PcSetupIntegrationEvent -Status Started -Message 'Teste de integracao iniciado.'

    $currentStage = 'SuiteDoProjeto'
    Write-PcSetupIntegrationEvent -Status Started -Message 'Executando a suite completa do projeto.' -Command 'powershell.exe' -Arguments @('-File', $testSuitePath)
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $testSuitePath
    if ($LASTEXITCODE -ne 0) { throw "A suite do projeto falhou com codigo $LASTEXITCODE." }
    Add-PcSetupIntegrationStep -Name 'Suite do projeto' -Status PASS -Detail 'Todos os testes automatizados passaram.'
    Write-PcSetupIntegrationEvent -Status Succeeded -Message 'Suite completa aprovada.'

    $currentStage = 'Windows'
    $verifyArguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$verifyPath`" -Config `"$($configuration._ConfigPath)`" -ReportPath `"$machineVerifyReportPath`""
    Write-PcSetupIntegrationEvent -Status Started -Message 'Solicitando UAC para a verificacao somente leitura do Windows.' -Command 'powershell.exe' -Arguments @('-File', $verifyPath, '-Config', $configuration._ConfigPath, '-ReportPath', $machineVerifyReportPath)
    $process = Start-Process -FilePath $windowsPowerShell -ArgumentList $verifyArguments -Verb RunAs -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "A verificacao do Windows falhou com codigo $($process.ExitCode). Relatorio: $machineVerifyReportPath" }
    Add-PcSetupIntegrationStep -Name 'Windows' -Status PASS -Detail $machineVerifyReportPath
    Write-PcSetupIntegrationEvent -Status Succeeded -Message 'Estado do Windows validado.'

    $environments = @()
    if ($configuration.Features.WSL) {
        $environments = @(Get-PcSetupWslEnvironments -Configuration $configuration |
            Where-Object { $_.Enabled -and $_.WindowsAccount -eq $env:USERNAME } |
            Sort-Object -Property @{ Expression = 'Default'; Descending = $true }, Name)
    }
    foreach ($environment in $environments) {
        $currentStage = "WSL/$($environment.Name)"
        Write-PcSetupIntegrationEvent -Status Started -Message "Validando o ambiente WSL $($environment.Name)." -Command 'wsl\verify.ps1' -Arguments @('-Config', $configuration._ConfigPath, '-Environment', $environment.Name)
        & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $wslVerifyPath -Config $configuration._ConfigPath -Environment $environment.Name | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "A verificacao WSL falhou para $($environment.Name) com codigo $LASTEXITCODE." }
        Add-PcSetupIntegrationStep -Name "WSL $($environment.Name)" -Status PASS -Detail 'Ambiente e ferramentas validados.'
        Write-PcSetupIntegrationEvent -Status Succeeded -Message "Ambiente WSL $($environment.Name) validado."
    }
    if ($environments.Count -eq 0) {
        Add-PcSetupIntegrationStep -Name 'WSL' -Status PASS -Detail 'Nenhum ambiente WSL habilitado para esta conta.'
    }

    $currentStage = 'Conclusao'
    Write-PcSetupIntegrationEvent -Status Succeeded -Message 'Teste de integracao concluido.'
}
catch {
    $failure = $_
    Add-PcSetupIntegrationStep -Name $currentStage -Status FAIL -Detail $failure.Exception.Message
    Write-PcSetupIntegrationEvent -Status Failed -Message $failure.Exception.Message
}

$report = [ordered]@{
    SchemaVersion = 1
    GeneratedAt   = (Get-Date).ToString('o')
    Status        = if ($null -eq $failure) { 'PASS' } else { 'FAIL' }
    Profile       = $configuration.ProfileName
    WindowsUser   = $env:USERNAME
    Steps         = @($steps)
    MachineVerifyReport = $machineVerifyReportPath
    ExecutionLog  = if ($null -ne $executionLog) { $executionLog.Path } else { $null }
    Error         = if ($null -ne $failure) { $failure.Exception.Message } else { $null }
}
Write-PcSetupJson -InputObject $report -Path $reportPath | Out-Null
Write-Host "`n[RELATORIO] $reportPath"
if ($null -ne $failure) {
    Write-Host "[ERRO] $($failure.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host '[OK] Teste de integracao concluido.' -ForegroundColor Green
