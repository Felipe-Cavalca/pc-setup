#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $root 'scripts\lib\PcSetup.PlanSummary.psm1') -Force

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$configuration = Import-PcSetupConfiguration -Path (Join-Path $root 'config\machine.psd1')
Assert-True $configuration.PlanSummary.Enabled 'O perfil padrao deve gerar o resumo legivel do plano.'
Assert-True ($configuration.PlanSummary.Formats -contains 'Html' -and $configuration.PlanSummary.Formats -contains 'Markdown') 'O plano legivel deve oferecer HTML e Markdown.'

$plan = [pscustomobject]@{
    CompletedAt = '2026-08-24T18:00:00-03:00'
    Profile = 'felipe-adaptive'
    Windows = [pscustomobject]@{ ProductName = 'Windows 11 Pro'; DisplayVersion = '24H2'; Build = 26100 }
    Storage = [pscustomobject]@{ SystemRoot = 'C:\'; DataRoot = 'D:\'; DataMode = 'SecondaryDisk' }
    Steps = @(
        [pscustomobject]@{
            Step = 'Packages'; Mode = 'Plan'
            Items = @([pscustomobject]@{ PackageId = 'Example.<Tool>'; Version = ''; Scope = 'machine'; Action = 'InstallOrUpdate' })
        }
        [pscustomobject]@{ Step = 'Personalization'; Mode = 'Plan'; Enabled = $false; Action = 'None' }
    )
}

$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ('pc-setup-plan-summary-' + [guid]::NewGuid().ToString('N'))
try {
    $jsonPath = 'C:\ProgramData\pc-setup\reports\pc-setup-plan-20260824-180000.json'
    $result = Write-PcSetupPlanSummaryFiles -Plan $plan -JsonPath $jsonPath -OutputDirectory $temporaryDirectory -FileBaseName 'PLANO-PC-SETUP' -Formats @('Html', 'Markdown')
    $htmlPath = Join-Path $temporaryDirectory 'PLANO-PC-SETUP.html'
    $markdownPath = Join-Path $temporaryDirectory 'PLANO-PC-SETUP.md'
    Assert-True ((Test-Path -LiteralPath $htmlPath -PathType Leaf) -and (Test-Path -LiteralPath $markdownPath -PathType Leaf)) 'Os dois arquivos legiveis devem ser gravados com nome estavel.'
    Assert-True (@($result.Files).Count -eq 2) 'O resultado deve listar os dois arquivos gravados.'

    $html = Get-Content -LiteralPath $htmlPath -Raw -Encoding UTF8
    $markdown = Get-Content -LiteralPath $markdownPath -Raw -Encoding UTF8
    Assert-True ($html -match 'PREVIA: nenhuma alteracao foi aplicada' -and $markdown -match 'PREVIA.*Nenhuma alteracao foi aplicada') 'Os formatos devem deixar claro que o plano nao aplica mudancas.'
    Assert-True ($html -match 'Example\.&lt;Tool&gt;' -and $html -notmatch 'Example\.<Tool>') 'O HTML deve escapar os dados do plano.'
    Assert-True ($markdown -match 'Instalar ou atualizar' -and $markdown.Contains($jsonPath)) 'O Markdown deve ser legivel e apontar para o JSON tecnico.'

    $bootstrap = Get-Content -LiteralPath (Join-Path $root 'bootstrap.ps1') -Raw -Encoding UTF8
    $launcher = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-PcSetup.ps1') -Raw -Encoding UTF8
    Assert-True ($bootstrap -match 'Write-PcSetupPlanSummaryFiles' -and $bootstrap -match 'ReadableReports') 'O bootstrap deve gerar o resumo depois do JSON e registrar os caminhos no recibo.'
    Assert-True ($launcher -match 'PC_SETUP_CALLER_DESKTOP') 'O fluxo elevado deve preservar a Area de Trabalho da conta que iniciou o launcher.'
}
finally {
    if (Test-Path -LiteralPath $temporaryDirectory) { Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force }
}

Write-Host 'PASS: plano tecnico gera copias HTML e Markdown legiveis e seguras.' -ForegroundColor Green
