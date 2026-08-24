#requires -Version 5.1
[CmdletBinding()]
param([string]$Config = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path $root 'config\machine.psd1' }
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Audit.psm1') -Force

try {
    $configuration = Import-PcSetupConfiguration -Path $Config
    if (-not $configuration.MachineAudit.Enabled) { throw 'O resumo da maquina esta desabilitado na configuracao.' }
    $systemRoot = [IO.Path]::GetPathRoot($env:SystemRoot)
    $outputDirectory = Resolve-PcSetupTemplate -Value ([string]$configuration.MachineAudit.OutputDirectory) -Configuration $configuration -SystemRoot $systemRoot
    $outputDirectory = [IO.Path]::GetFullPath($outputDirectory)
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

    $audit = Get-PcSetupMachineAuditData -Configuration $configuration
    $written = @()
    foreach ($format in @($configuration.MachineAudit.Formats)) {
        if ([string]$format -eq 'Html') {
            $path = Join-Path $outputDirectory ([string]$configuration.MachineAudit.FileBaseName + '.html')
            ConvertTo-PcSetupMachineSummaryHtml -Audit $audit | Set-Content -LiteralPath $path -Encoding UTF8
            $written += $path
        }
        elseif ([string]$format -eq 'Markdown') {
            $path = Join-Path $outputDirectory ([string]$configuration.MachineAudit.FileBaseName + '.md')
            ConvertTo-PcSetupMachineSummaryMarkdown -Audit $audit | Set-Content -LiteralPath $path -Encoding UTF8
            $written += $path
        }
    }

    $reportDirectory = Get-PcSetupRuntimePath -Configuration $configuration -Key 'UserReportDirectory' -SystemRoot $systemRoot
    $jsonPath = Join-Path $reportDirectory ('machine-audit-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    Write-PcSetupJson -InputObject $audit -Path $jsonPath | Out-Null
    Write-Host "[OK] Resumo da maquina atualizado: $($written -join ', ')" -ForegroundColor Green
    Write-Host "Relatorio JSON: $jsonPath" -ForegroundColor Cyan
    [pscustomobject]@{ Status = 'Completed'; Files = $written; JsonReport = $jsonPath }
    exit 0
}
catch {
    Write-Host "[ERRO] Nao foi possivel gerar o resumo da maquina: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
