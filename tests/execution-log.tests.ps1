#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\lib\PcSetup.ExecutionLog.psm1') -Force

function Assert-True($Value, [string]$Message) { if (-not $Value) { throw $Message } }

$directory = Join-Path $env:TEMP ('pc-setup-execution-log-' + [guid]::NewGuid().ToString('N'))
try {
    $log = New-PcSetupExecutionLog -Directory $directory -Operation 'Teste'
    $event = Write-PcSetupExecutionEvent -Log $log -Stage 'Winget' -Status Started -Message 'token=segredo-mensagem' -Command 'winget.exe' -Arguments @('install', '--token', 'segredo-argumento', '--api-key=segredo-inline', 'PASSWORD=segredo-env', '--id', 'Google.Chrome') -Data @{ User = 'Felipe'; Credential = 'segredo-dado' }

    Assert-True (Test-Path -LiteralPath $log.Path -PathType Leaf) 'O log JSONL deve ser criado no diretorio solicitado.'
    $raw = Get-Content -LiteralPath $log.Path -Raw -Encoding UTF8
    Assert-True ($raw -notmatch 'segredo-') 'Nenhum valor sensivel pode permanecer no arquivo de log.'
    Assert-True ($raw -match '\[REDACTED\]') 'Valores sensiveis devem ser substituidos por marcador explicito.'
    $record = $raw.Trim() | ConvertFrom-Json
    Assert-True ($record.SchemaVersion -eq 1 -and $record.SessionId -eq $log.SessionId) 'Cada evento deve preservar schema e identificador da sessao.'
    Assert-True ($record.Command -eq 'winget.exe' -and $record.Arguments -contains 'Google.Chrome') 'Comando e argumentos nao sensiveis devem permanecer diagnosticaveis.'
    Assert-True ($record.Data.User -eq 'Felipe' -and $record.Data.Credential -eq '[REDACTED]') 'Dados estruturados devem preservar somente os campos seguros.'
    Assert-True ($event.Status -eq 'Started') 'A escrita deve devolver o evento registrado.'
}
finally {
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
}

Write-Host 'PASS: log de execucao estruturado e sanitizado.' -ForegroundColor Green
