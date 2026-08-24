#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Assert-True($Value, [string]$Message) { if (-not $Value) { throw $Message } }

$parseErrors = @()
Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psm1') } | ForEach-Object {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    $parseErrors += @($errors)
}
Assert-True ($parseErrors.Count -eq 0) "Existem erros de sintaxe: $($parseErrors.Message -join '; ')"

$config = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'config\machine.psd1')
Assert-True (-not $config.Security.ManageBitLocker) 'BitLocker deve permanecer nao gerenciado por padrao.'
Assert-True ($config.Debloat.Enabled -and $config.Debloat.Preset -eq 'RunDefaults') 'Debloat deve usar o preset previamente definido.'
Assert-True (-not $config.Debloat.RemoveGamingApps) 'Debloat nao deve remover aplicativos de jogos.'
Assert-True ($config.Execution.Mode -eq 'Interactive' -and $config.Storage.Data.SecondaryDiskPolicy -eq 'Ask') 'O disco deve ser perguntado no perfil Felipe.'
Assert-True (-not $config.Accounts.ContainsKey('God')) 'Conta God deve ter sido removida.'
Assert-True (-not $config.Accounts.ContainsKey('Codex')) 'O agente nao deve ser uma conta Windows.'
Assert-True ($config.Agent.Enabled) 'O usuario Linux agent deve estar habilitado no perfil padrao.'
Assert-True ($config.Agent.Harness.Enabled -and $config.Agent.Harness.Package -eq '@openai/codex') 'Codex deve ser instalado automaticamente para o agente.'
Assert-True ($config.Agent.Memory.Enabled -and $config.Agent.Memory.Repository -eq 'akitaonrails/ai-memory') 'ai-memory deve estar habilitado para o agente no perfil padrao.'
Assert-True ($config.Agent.Memory.Version -eq 'latest' -and $config.Agent.Memory.RequireAssetDigest) 'ai-memory deve usar a release atual com digest publicado.'
Assert-True ($config.Agent.Memory.Client -eq 'codex' -and $config.Agent.Memory.ProjectStrategy -eq 'repo-root') 'ai-memory deve integrar o Codex por raiz do repositorio.'
Assert-True ($config.Agent.Memory.ServerUrl -eq 'http://127.0.0.1:49374') 'ai-memory deve permanecer restrito ao loopback.'
Assert-True ($config.Agent.Workspace.Mode -eq 'SelectedProjectOnly') 'O agente deve acessar somente o projeto selecionado.'
Assert-True (-not $config.Agent.VirtualMachine.Enabled) 'Nenhuma VM deve ser criada por padrao.'
Assert-True (@($config.Security.HyperVAdministratorAccounts) -contains 'DailyUser') 'O usuario diario deve administrar o Hyper-V.'
Assert-True ($config.Accounts.Public.Enabled -and $config.Accounts.Public.Role -eq 'Standard') 'Conta Publico deve estar habilitada sem privilegio administrativo.'

$debloatScript = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts\50-debloat-akita.ps1')
Assert-True ($debloatScript -match "'-RunDefaults', '-Silent', '-AppRemovalTarget'") 'O wrapper deve aplicar o preset fixo de forma silenciosa.'
Assert-True ($config.Debloat.ArchiveSha256 -eq 'e97c8e36698c7b543da0b77cc34439c1a0b4917525b45a9d1ae7a02e23d4711d') 'O ZIP revisado do debloat deve ter SHA-256 fixo.'

$basePackages = Get-Content -LiteralPath (Join-Path $root 'config\packages\base.txt') | Where-Object { $_ -and -not $_.StartsWith('#') }
Assert-True (@($basePackages) -contains 'Google.Chrome|machine') 'Chrome deve estar instalado para todas as contas no escopo de maquina.'
Assert-True (@($basePackages | Where-Object { $_ -match 'Brave|Discord|Spotify|WhatsApp' }).Count -eq 0) 'O perfil base nao deve adicionar outros aplicativos solicitados anteriormente para a conta publica.'

$launcher = Get-Content -Raw -LiteralPath (Join-Path $root 'INSTALAR.cmd')
Assert-True ($launcher -match 'Start-PcSetupUpdate\.ps1' -and $launcher -match '-LauncherName INSTALAR\.cmd') 'O instalador deve chamar o orquestrador completo.'
$assistedScript = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts\Start-PcSetup.ps1')
Assert-True ($assistedScript -match 'bootstrap\.ps1' -and $assistedScript -match 'verify\.ps1') 'O fluxo assistido deve executar plano, aplicacao e verificacao.'
$agentLauncher = Get-Content -Raw -LiteralPath (Join-Path $root 'AGENTE.cmd')
Assert-True ($agentLauncher -match 'Start-Agent\.ps1') 'O launcher do agente deve chamar o fluxo WSL isolado.'
$updateLauncher = Get-Content -Raw -LiteralPath (Join-Path $root 'ATUALIZAR.cmd')
Assert-True ($updateLauncher -match 'Start-PcSetupUpdate\.ps1') 'O atualizador deve chamar o fluxo de reconciliacao.'

Write-Host 'PASS: sintaxe e invariantes de seguranca.' -ForegroundColor Green
