#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Assert-True($Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}

$launcher = Get-Content -LiteralPath (Join-Path $root 'DEBLOAT.cmd') -Raw
$standalone = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-Debloat.ps1') -Raw
$assisted = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-PcSetup.ps1') -Raw
$bootstrap = Get-Content -LiteralPath (Join-Path $root 'scripts\bootstrap.ps1') -Raw

Assert-True ($launcher -match 'Start-Debloat\.ps1') 'DEBLOAT.cmd deve chamar o fluxo independente.'
Assert-True ($standalone -match '-Plan' -and $standalone -match 'Read-Host.+Digite S' -and $standalone -match '-Apply -ConfirmReviewed') 'O debloat independente deve mostrar o plano, pedir confirmacao e aplicar somente o perfil revisado.'
Assert-True ($standalone -match 'Start-Process[\s\S]+-Verb RunAs[\s\S]+-Wait') 'O debloat independente deve solicitar elevacao e aguardar o resultado.'
Assert-True ($standalone -match 'ApplyConfirmed' -and $standalone -match 'Pressione ENTER para fechar') 'A janela elevada deve preservar o resultado ou erro do debloat para leitura.'
Assert-True ($assisted -match '\$includeDebloat = \$LauncherName -eq ''INSTALAR\.cmd''' -and $assisted -match 'IncludeDebloat:\$includeDebloat') 'A escolha do debloat integrado deve depender do launcher de instalacao.'
Assert-True ($bootstrap -match '\$includeConfiguredDebloat' -and $bootstrap -match 'IncludeDebloat\s*=\s*\$includeConfiguredDebloat') 'Plano e estado de retomada devem registrar a inclusao do debloat.'
Assert-True ($bootstrap -match 'Name ''Debloat''[\s\S]+ConfirmReviewed = \$true') 'A instalacao confirmada deve aplicar o debloat dentro da sessao protegida.'

Write-Host 'PASS: debloat integrado na instalacao e disponivel em launcher independente.' -ForegroundColor Green
