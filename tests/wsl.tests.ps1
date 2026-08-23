#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $root 'wsl\PcSetup.Wsl.psm1') -Force

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -ne $Actual) { throw "$Message Esperado: '$Expected'. Atual: '$Actual'." }
}
function Assert-True($Value, [string]$Message) { if (-not $Value) { throw $Message } }

$configPath = Join-Path $root 'config\machine.psd1'
$configuration = Import-PcSetupConfiguration -Path $configPath
$environments = @(Get-PcSetupWslEnvironments -Configuration $configuration | Where-Object Enabled)
Assert-Equal 2 $environments.Count 'O perfil padrao deve declarar os ambientes WSL diario e Agent.'
Assert-True (-not $configuration.Accounts.ContainsKey('Codex')) 'Codex nao deve existir como conta Windows.'
Assert-True (-not $configuration.Accounts.ContainsKey('God')) 'God nao deve existir como conta Windows.'
Assert-Equal 'AiJail' $configuration.Agent.Isolation 'O agente deve usar ai-jail.'
Assert-Equal '@openai/codex' $configuration.Agent.Harness.Package 'Codex deve ser o harness padrao.'
Assert-Equal 'latest' $configuration.Agent.Harness.Version 'O atualizador deve buscar a versao atual do Codex.'
Assert-Equal 'SelectedProjectOnly' $configuration.Agent.Workspace.Mode 'Somente o projeto selecionado deve ser liberado.'
Assert-Equal $false $configuration.Agent.VirtualMachine.Enabled 'Nenhuma VM do agente deve ser criada por padrao.'

$daily = $environments | Where-Object Name -eq 'DailyUser'
$agent = $environments | Where-Object Name -eq 'Agent'
Assert-Equal 'Felipe' $daily.WindowsAccount 'O WSL diario deve pertencer a conta Windows Felipe.'
Assert-Equal 'Felipe' $agent.WindowsAccount 'O WSL do agente deve ser chamado pela conta Windows Felipe.'
Assert-Equal 'Ubuntu-24.04' $daily.Distribution 'A distribuicao deve ser fixa e reproduzivel.'
Assert-Equal $daily.Distribution $agent.Distribution 'O agente deve compartilhar a distribuicao para economizar espaco.'
Assert-Equal $true $daily.Default 'O ambiente diario deve preservar o usuario WSL padrao.'
Assert-Equal $false $agent.Default 'O ambiente Agent nao deve assumir a sessao WSL.'

$dailyProfile = Import-PcSetupWslProfile -Configuration $configuration -Environment $daily
$agentProfile = Import-PcSetupWslProfile -Configuration $configuration -Environment $agent
Assert-Equal 'felipe' $dailyProfile.LinuxUser 'O perfil diario deve ter usuario Linux proprio.'
Assert-Equal 'agent' $agentProfile.LinuxUser 'O perfil Agent deve ter usuario Linux proprio.'
Assert-Equal '/home/felipe/Dev' $dailyProfile.ProjectRoot 'O diretorio de projetos deve ser resolvido no filesystem Linux.'
Assert-True (@($dailyProfile.Packages).Count -gt 0) 'O perfil WSL deve declarar os pacotes APT.'
Assert-Equal $true $agentProfile.RequireNoSudo 'O usuario agent deve permanecer sem sudo.'
Assert-Equal 'pcsetup-agent' $agentProfile.SharedGroup 'O workspace do agente deve usar um grupo compartilhado explicito.'
Assert-True (@($agentProfile.SharedWith) -contains 'felipe') 'Felipe deve acessar o workspace do agente no uso diario.'
Assert-Equal 'latest' $agentProfile.AiJail.Version 'O perfil deve buscar a release estavel atual do ai-jail.'
Assert-Equal 'akitaonrails/ai-jail' $agentProfile.AiJail.Repository 'A origem do ai-jail deve ser explicita.'
Assert-True ([string]::IsNullOrWhiteSpace([string]$agentProfile.AiJail.Sha256)) 'A politica latest nao deve conservar o hash de uma release antiga.'
Assert-Equal $true $agentProfile.AiJail.RequireAssetDigest 'A release atual deve exigir o digest publicado pelo GitHub.'
Assert-True (@($agentProfile.Packages) -contains 'nodejs' -and @($agentProfile.Packages) -contains 'npm') 'O perfil Agent deve instalar o runtime do harness.'
Assert-Equal '@openai/codex' $agentProfile.Harness.Package 'O perfil resolvido deve receber o harness configurado.'
Assert-Equal 'codex' $agentProfile.Harness.Command 'O comando do harness deve acompanhar Agent.DefaultCommand.'

$automaticTarget = Resolve-PcSetupWslTarget -Configuration $configuration -CurrentWindowsAccount 'Felipe'
Assert-Equal 'DailyUser' $automaticTarget.Environment.Name 'A selecao automatica deve escolher o ambiente WSL padrao.'
Assert-Equal 'felipe' (Get-PcSetupExpectedWslDefaultUser -Configuration $configuration -Environment $agent) 'Aplicar Agent nao deve trocar o usuario WSL padrao.'

$oneDiskConfiguration = Import-PcSetupConfiguration -Path (Join-Path $root 'config\examples\machine-one-disk.psd1')
$oneDiskEnvironments = @(Get-PcSetupWslEnvironments -Configuration $oneDiskConfiguration)
Assert-Equal 2 $oneDiskEnvironments.Count 'O exemplo generico deve documentar os dois ambientes configuraveis.'
Assert-True (@($oneDiskEnvironments | Where-Object Enabled).Count -eq 0) 'O WSL deve acompanhar o recurso global desabilitado no exemplo minimo.'

$dailyPlan = & (Join-Path $root 'wsl\bootstrap.ps1') -Config $configPath -Environment DailyUser -Plan
$agentPlan = & (Join-Path $root 'wsl\bootstrap.ps1') -Config $configPath -Environment Agent -Plan
Assert-Equal 'Plan' $dailyPlan.Mode 'O bootstrap WSL deve oferecer plano sem alterar a maquina.'
Assert-Equal 'DailyUser' $dailyPlan.Environment 'O plano deve identificar o ambiente diario.'
Assert-Equal 'Agent' $agentPlan.Environment 'O plano deve identificar o ambiente Agent.'

$bootstrapPowerShell = Get-Content -LiteralPath (Join-Path $root 'wsl\bootstrap.ps1') -Raw
$bootstrapLinux = Get-Content -LiteralPath (Join-Path $root 'wsl\linux\bootstrap.sh') -Raw
$verifyLinux = Get-Content -LiteralPath (Join-Path $root 'wsl\linux\verify.sh') -Raw
$releaseHelper = Get-Content -LiteralPath (Join-Path $root 'wsl\linux\github-release.sh') -Raw
Assert-True ($bootstrapPowerShell -match '--terminate' -and $bootstrapPowerShell -match 'Get-PcSetupWslDefaultUser') 'O bootstrap deve reiniciar a distribuicao e conferir o usuario padrao.'
Assert-True ($bootstrapLinux -match 'set_default_user' -and $bootstrapLinux -match '/etc/wsl\.conf') 'O bootstrap deve preservar explicitamente o usuario WSL padrao.'
Assert-True ($bootstrapLinux -match 'installed\.tsv' -and $bootstrapLinux -match 'dpkg-query') 'O bootstrap Linux deve registrar as versoes instaladas.'
Assert-True ($bootstrapLinux -match 'canonicalize-missing') 'O bootstrap Linux deve recusar uma raiz de projetos desviada por symlink.'
Assert-True ($bootstrapLinux -match 'passwd --lock' -and $bootstrapLinux -match 'sudo wheel docker lxd' -and $verifyLinux -match 'Agent privilege') 'O bootstrap e o verify devem impedir senha e grupos privilegiados no usuario agent.'
Assert-True ($releaseHelper -match '/releases/latest' -and $releaseHelper -match '\.digest' -and $bootstrapLinux -match 'sha256sum --check' -and $verifyLinux -match 'ai_jail_binary_sha256') 'A instalacao e a verificacao devem resolver e validar a release atual do ai-jail.'
Assert-True ($bootstrapLinux -match 'npm install --global' -and $bootstrapLinux -match 'harness_version' -and $verifyLinux -match 'Agent harness') 'O bootstrap deve instalar o harness e o verify deve conferir sua versao real.'

$wslModule = Get-Content -LiteralPath (Join-Path $root 'wsl\PcSetup.Wsl.psm1') -Raw
Assert-True ($wslModule -match 'Get-PcSetupWslInstalledState' -and $bootstrapPowerShell -match 'InstalledState') 'Os relatorios WSL devem registrar as versoes realmente instaladas.'

$agentLauncher = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-Agent.ps1') -Raw
Assert-True ($agentLauncher -match '--agent-state' -and $agentLauncher -match '--no-docker' -and $agentLauncher -match '--no-inherit-env' -and $agentLauncher -match 'canonicalize-existing' -and $agentLauncher -match 'Test-SafeAgentProjectPath') 'O launcher deve aplicar capacidades explicitas e recusar workspaces amplos ou nao canonicos.'

Write-Host 'PASS: WSL convergente com usuario agent e ai-jail atual validado.' -ForegroundColor Green
