#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

function Assert-True($Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}

$machine = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'config\machine.psd1')
$agentProfile = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'wsl\profiles\agent.psd1')
Assert-True ($machine.Agent.Memory.Version -eq 'latest') 'Agent.Memory deve continuar resolvendo a release estavel atual.'
Assert-True ($machine.Agent.Harness.Version -eq 'latest') 'O Codex deve continuar sendo atualizado para a versao atual.'
Assert-True ($agentProfile.AiJail.Version -eq 'latest') 'AiJail deve continuar resolvendo a release estavel atual.'
Assert-True ($machine.Agent.Memory.RequireAssetDigest -eq $true -and $agentProfile.AiJail.RequireAssetDigest -eq $true) 'As releases latest devem continuar exigindo digest publicado.'

$bootstrap = Get-Content -LiteralPath (Join-Path $root 'wsl\bootstrap.ps1') -Raw
$helperPath = Join-Path $root 'wsl\linux\prepare-ai-memory-upgrade.sh'
Assert-True (Test-Path -LiteralPath $helperPath -PathType Leaf) 'O helper de upgrade do ai-memory deve existir.'
$helper = Get-Content -LiteralPath $helperPath -Raw

$calls = [regex]::Matches($bootstrap, 'Invoke-PcSetupAiMemoryUpgradePreparation -Distribution')
$mainBootstrapIndex = $bootstrap.IndexOf('$bootstrapResult = Invoke-PcSetupWslLinuxScript', [StringComparison]::Ordinal)
Assert-True ($calls.Count -eq 2) 'O helper deve rodar antes e depois do bootstrap Linux.'
Assert-True ($mainBootstrapIndex -ge 0 -and $calls[0].Index -lt $mainBootstrapIndex -and $calls[1].Index -gt $mainBootstrapIndex) 'A primeira preparacao deve proteger a migracao existente e a segunda deve convergir instalacoes novas.'

Assert-True ($helper -match 'ai-memory-backups') 'O backup de migracao deve ficar fora do diretorio de dados do ai-memory.'
Assert-True ($helper -match 'AI_MEMORY_BACKUP_DIR=') 'O servico deve receber AI_MEMORY_BACKUP_DIR explicitamente.'
Assert-True ($helper -match 'ReadWritePaths=\$ai_memory_backup_directory') 'ProtectHome deve liberar somente o diretorio dedicado de backup.'
Assert-True ($helper -match 'mode 0700') 'O diretorio de backup deve permanecer privado para o usuario do agente.'
Assert-True ($helper -match 'systemctl daemon-reload') 'O drop-in do systemd deve ser recarregado antes do bootstrap reiniciar o servico.'
Assert-True ($helper -match 'does not exist yet') 'Instalacoes novas devem tolerar a primeira passagem antes da criacao do usuario Linux.'

Write-Host 'PASS: latest do agente e migracao segura do ai-memory 2 validados.' -ForegroundColor Green
