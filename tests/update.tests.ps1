#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
function Assert-True($Value, [string]$Message) { if (-not $Value) { throw $Message } }

$installLauncher = Get-Content -LiteralPath (Join-Path $root 'INSTALAR.cmd') -Raw
$updateLauncher = Get-Content -LiteralPath (Join-Path $root 'ATUALIZAR.cmd') -Raw
$update = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-PcSetupUpdate.ps1') -Raw
$assisted = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-PcSetup.ps1') -Raw
$bootstrap = Get-Content -LiteralPath (Join-Path $root 'bootstrap.ps1') -Raw
$features = Get-Content -LiteralPath (Join-Path $root 'scripts\10-windows-features.ps1') -Raw

Assert-True ($installLauncher -match 'Start-PcSetupUpdate\.ps1' -and $installLauncher -match '-LauncherName INSTALAR\.cmd') 'INSTALAR.cmd deve usar o orquestrador completo.'
Assert-True ($updateLauncher -match 'Start-PcSetupUpdate\.ps1' -and $updateLauncher -match '-LauncherName ATUALIZAR\.cmd') 'ATUALIZAR.cmd deve usar o orquestrador completo.'
Assert-True ($update -match "ValidateSet\('INSTALAR\.cmd','ATUALIZAR\.cmd'\)" -and $update -match '-LauncherName \$LauncherName') 'O orquestrador deve preservar a identidade do launcher no fluxo protegido.'
Assert-True ($update -match '-Config \$configuration\._ConfigPath' -and $assisted -match '\[string\]\$Config') 'O perfil selecionado deve chegar ao processo elevado do Windows.'
Assert-True ($update -match 'Get-PcSetupWslEnvironments' -and $update -match 'wsl\\bootstrap\.ps1' -and $update -match 'wsl\\verify\.ps1') 'O atualizador deve planejar, aplicar e validar os ambientes WSL habilitados.'
Assert-True ($update -match 'Expression = ''Default''; Descending = \$true') 'O usuario WSL padrao deve ser aplicado antes do agente.'
Assert-True ($update -match 'user-reconcile-state\.json' -and $update -match 'Get-CompletedWindowsApplyReport') 'A retomada das fases do usuario deve depender do estado e de um relatorio Windows concluido.'
Assert-True ($update -match '\$pendingUserPhase\.ConfigSha256 -eq \$configHash' -and $update -match '\$pendingUserPhase\.ProjectSha256 -eq \$projectHash') 'A retomada deve exigir os mesmos hashes de configuracao e projeto.'
Assert-True ($update -match 'user-reconcile-completed\.json' -and $update -match '\$userPhaseAlreadyCompleted') 'Uma reconciliacao concluida deve ser distinguida de uma retomada pendente.'
Assert-True ($update -match '\$isDailyUser' -and $update -match '\[TROCA DE CONTA\]') 'A fase de maquina deve poder comecar em outra conta e concluir na conta diaria configurada.'
Assert-True ($update -match '90-user-profile\.ps1' -and $update -match 'pacotes, personalizacao e WSL') 'A retomada deve abranger todas as fases da conta diaria.'
Assert-True ($update -match 'Save-PcSetupKnownGood\.ps1' -and $update -match 'CaptureKnownGood') 'A reconciliacao concluida deve registrar as versoes conhecidas como boas.'
Assert-True ($update -match 'Remove-Item -LiteralPath \$reconcileStatePath -Force') 'O estado de retomada deve ser removido depois da reconciliacao.'
Assert-True ($update -notmatch 'Read-Host\s+.*Quer reconciliar') 'O WSL nao deve pedir uma segunda confirmacao depois da aplicacao do Windows.'
Assert-True ($assisted -match '\[switch\]\$NoPause' -and $assisted -match "ValidateSet\('INSTALAR\.cmd','ATUALIZAR\.cmd'\)") 'O fluxo protegido deve suportar composicao sem perder retomada apos reinicio.'
Assert-True ($assisted -match 'Write-PcSetupFailureDiagnostic' -and $assisted -match 'last-error\.json' -and $assisted -match 'ScriptStackTrace') 'O processo elevado deve persistir a mensagem e o contexto da falha.'
Assert-True ($update -match 'Get-PcSetupWindowsFailureDiagnostic' -and $update -match 'Detalhe:.*failure\.Message' -and $update -match 'Diagnostico:.*failure\.Path') 'O orquestrador deve recuperar e mostrar o erro do processo elevado na janela principal.'
Assert-True ($update -match 'PcSetup\.ExecutionLog\.psm1' -and $update -match 'Write-PcSetupExecutionEvent' -and $update -match 'Log da sessao') 'O orquestrador deve registrar e apresentar o log cronologico sanitizado.'
Assert-True ($assisted -match "'verify-'" -and $assisted -match "Where-Object Status -eq 'FAIL'" -and $assisted -match '\$failedDetails') 'Falhas da verificacao final devem ser convertidas em diagnostico legivel.'
Assert-True ($update -match "'verify-\*\.json'" -and $update -match '\$report\.Checks' -and $update -match 'A validacao final encontrou') 'O orquestrador deve usar o relatorio Verify como fallback de diagnostico.'
Assert-True ($bootstrap -match "Stage -in @\('Starting', 'RestartRequired'\)") 'A retomada apos reinicio deve reconvergir os recursos do Windows antes de continuar.'
Assert-True ($features -match "State -notin @\('Enabled', 'EnablePending'\)" -and $features -match "State -eq 'EnablePending'") 'A aplicacao deve validar o estado efetivo de cada recurso e preservar a necessidade de reinicio.'

Write-Host 'PASS: atualizador idempotente e fluxo de retomada.' -ForegroundColor Green
