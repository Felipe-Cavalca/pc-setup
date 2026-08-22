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
Assert-Equal 2 $environments.Count 'O perfil padrao deve separar os ambientes WSL diario e Codex.'
Assert-Equal 'Standard' $configuration.Accounts.Codex.Role 'Codex deve permanecer usuario padrao no Windows.'
Assert-Equal 'Administrator' $configuration.Accounts.God.Role 'God deve permanecer definido como conta administrativa de emergencia.'
Assert-Equal $false $configuration.Accounts.God.Enabled 'God nao deve ser criado automaticamente.'

$daily = $environments | Where-Object Name -eq 'DailyUser'
$codex = $environments | Where-Object Name -eq 'Codex'
Assert-Equal 'Felipe' $daily.WindowsAccount 'O WSL diario deve pertencer a conta Windows Felipe.'
Assert-Equal 'Codex' $codex.WindowsAccount 'O WSL do agente deve pertencer a conta Windows Codex.'
Assert-Equal 'Ubuntu-24.04' $daily.Distribution 'A distribuicao deve ser fixa e reproduzivel.'
Assert-Equal $daily.Distribution $codex.Distribution 'Cada conta pode registrar separadamente a mesma distribuicao.'

$dailyProfile = Import-PcSetupWslProfile -Configuration $configuration -Environment $daily
$codexProfile = Import-PcSetupWslProfile -Configuration $configuration -Environment $codex
Assert-Equal 'felipe' $dailyProfile.LinuxUser 'O perfil diario deve ter usuario Linux proprio.'
Assert-Equal 'codex' $codexProfile.LinuxUser 'O perfil Codex deve ter usuario Linux proprio.'
Assert-Equal '/home/felipe/Dev' $dailyProfile.ProjectRoot 'O diretorio de projetos deve ser resolvido no filesystem Linux.'
Assert-True (@($dailyProfile.Packages).Count -gt 0) 'O perfil WSL deve declarar os pacotes APT.'

$oneDiskConfiguration = Import-PcSetupConfiguration -Path (Join-Path $root 'config\examples\machine-one-disk.psd1')
$oneDiskEnvironments = @(Get-PcSetupWslEnvironments -Configuration $oneDiskConfiguration)
Assert-Equal 1 $oneDiskEnvironments.Count 'O exemplo generico deve declarar apenas o ambiente do usuario diario.'
Assert-Equal $false $oneDiskEnvironments[0].Enabled 'O ambiente WSL deve acompanhar o recurso global desabilitado no exemplo minimo.'

$dailyPlan = & (Join-Path $root 'wsl\bootstrap.ps1') -Config $configPath -Environment DailyUser -Plan
$codexPlan = & (Join-Path $root 'wsl\bootstrap.ps1') -Config $configPath -Environment Codex -Plan
Assert-Equal 'Plan' $dailyPlan.Mode 'O bootstrap WSL deve oferecer plano sem alterar a maquina.'
Assert-Equal 'DailyUser' $dailyPlan.Environment 'O plano deve identificar o ambiente diario.'
Assert-Equal 'Codex' $codexPlan.Environment 'O plano deve identificar o ambiente Codex.'

$bootstrapPowerShell = Get-Content -LiteralPath (Join-Path $root 'wsl\bootstrap.ps1') -Raw
$bootstrapLinux = Get-Content -LiteralPath (Join-Path $root 'wsl\linux\bootstrap.sh') -Raw
$verifyLinux = Get-Content -LiteralPath (Join-Path $root 'wsl\linux\verify.sh') -Raw
Assert-True ($bootstrapPowerShell -match '--terminate' -and $bootstrapPowerShell -match 'Get-PcSetupWslDefaultUser') 'O bootstrap deve reiniciar a distribuicao e conferir o usuario padrao.'
Assert-True ($bootstrapLinux -match '/etc/wsl\.conf' -and $bootstrapLinux -match 'default=') 'O bootstrap deve configurar o usuario padrao pelo mecanismo oficial do WSL.'
Assert-True ($bootstrapLinux -match 'installed\.tsv' -and $bootstrapLinux -match 'dpkg-query') 'O bootstrap Linux deve registrar as versoes instaladas.'
Assert-True ($bootstrapLinux -match 'canonicalize-missing') 'O bootstrap Linux deve recusar uma raiz de projetos desviada por symlink.'
Assert-True ($verifyLinux -match 'recorded_version' -and $verifyLinux -match 'Project root') 'O verify Linux deve conferir estado, diretorio e versoes.'

Write-Host 'PASS: perfis e planos WSL separados e reproduziveis.' -ForegroundColor Green
