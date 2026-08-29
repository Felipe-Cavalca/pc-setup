#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\lib\PcSetup.Recovery.psm1'
Import-Module $modulePath -Force

function Assert-True($Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}

try {
    Stop-PcSetupChangeSession

    $missing = Resume-PcSetupChangeSession `
        -Description 'pc-setup ausente' `
        -SequenceNumber '42' `
        -SessionId ([guid]::NewGuid().ToString('N')) `
        -ReturnNullIfMissing `
        -ListAction { @() }
    Assert-True ($null -eq $missing) 'A retomada recuperavel deve retornar nulo quando o ponto salvo nao existe.'

    $bootstrap = Get-Content -Raw -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\bootstrap.ps1')
    Assert-True ($bootstrap -match 'apply-state-invalid-') 'O estado invalido deve ser arquivado para diagnostico.'
    Assert-True ($bootstrap -match 'if \(-not \$isResume\)\s*\{\s*\$restorePoint = Start-PcSetupChangeSession') 'A ausencia do ponto deve iniciar uma nova sessao protegida.'
    $resumeIndex = $bootstrap.IndexOf('$restorePoint = Resume-PcSetupChangeSession')
    $configurationMismatchIndex = $bootstrap.IndexOf("throw 'Existe uma aplicacao incompleta com outra configuracao")
    Assert-True ($resumeIndex -ge 0 -and $configurationMismatchIndex -gt $resumeIndex) 'Um ponto removido deve ser recuperado mesmo depois de atualizar os scripts.'

    Write-Host 'PASS: retomada com ponto removido reinicia uma aplicacao protegida.' -ForegroundColor Green
}
finally {
    Stop-PcSetupChangeSession
}
