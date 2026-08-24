#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Audit.psm1') -Force

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$audit = [pscustomobject]@{
    SchemaVersion = '1.0'
    GeneratedAt = '2026-08-24T12:00:00-03:00'
    Profile = 'teste'
    Sections = @(
        [pscustomobject]@{
            Title = 'Seguranca'
            Rows = @([pscustomobject][ordered]@{ Item = 'BitLocker C:'; Status = 'Manual'; Detalhe = 'Nao configurado pelo pc-setup' })
        }
        [pscustomobject]@{
            Title = 'Armazenamento e saude'
            Rows = @([pscustomobject][ordered]@{ Item = 'SSD <principal>'; Status = 'Healthy'; Detalhe = 'temperatura=35 C' })
        }
    )
}

$markdown = ConvertTo-PcSetupMachineSummaryMarkdown -Audit $audit
$html = ConvertTo-PcSetupMachineSummaryHtml -Audit $audit
Assert-True ($markdown -match '# Resumo da maquina' -and $markdown -match 'BitLocker C:') 'O Markdown deve conter titulo e dados da auditoria.'
Assert-True ($markdown -match 'Nao configura BitLocker') 'O Markdown deve explicar o limite informativo.'
Assert-True ($html -match '<meta charset="utf-8">' -and $html -match 'SSD &lt;principal&gt;') 'O HTML deve declarar UTF-8 e escapar conteudo.'
Assert-True ($html -notmatch 'SSD <principal>') 'O HTML nao pode inserir valores sem escape.'

Write-Host 'PASS: resumos HTML e Markdown sao legiveis e seguros.' -ForegroundColor Green
