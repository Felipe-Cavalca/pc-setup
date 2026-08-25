#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Winget.psm1') -Force

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FALHA: $Message" }
}

$configuration = Import-PcSetupConfiguration -Path (Join-Path $root 'config\machine.psd1')
$oneDisk = Import-PcSetupConfiguration -Path (Join-Path $root 'config\examples\machine-one-disk.psd1')
$agentEnvironment = Get-PcSetupWslEnvironments -Configuration $configuration | Where-Object Name -eq $configuration.Agent.Environment | Select-Object -First 1
$agentProfile = Import-PcSetupWslProfile -Configuration $configuration -Environment $agentEnvironment

Assert-True ($configuration.Windows.Edition -eq 'Professional') 'O perfil deve exigir EditionID Professional.'
Assert-True ($configuration.Reconciliation.Mode -eq 'Additive') 'A reconciliacao deve declarar o modo aditivo.'
Assert-True (-not $configuration.Reconciliation.RemoveUnlistedPackages) 'Pacotes ausentes nao podem ser removidos implicitamente.'
Assert-True ($configuration.Packages.PreferCurrentVersion -and $configuration.Packages.InstallScope -eq 'machine') 'Winget deve buscar versoes atuais em escopo de maquina.'
$packageDefinitions = @(Get-PcSetupPackageDefinitions -Configuration $configuration)
Assert-True (($packageDefinitions | Where-Object PackageId -eq 'Google.Chrome').Scope -eq 'machine') 'Chrome deve ficar disponivel para as contas locais.'
Assert-True (($packageDefinitions | Where-Object PackageId -eq 'Microsoft.WindowsTerminal').Scope -eq 'user') 'Windows Terminal deve respeitar o escopo suportado pelo pacote.'
$fakeExport = [pscustomobject]@{ Sources = @([pscustomobject]@{
    SourceDetails = [pscustomobject]@{ Identifier = 'winget' }
    Packages = @(
        [pscustomobject]@{ PackageIdentifier = 'Google.Chrome'; Version = '1.0' },
        [pscustomobject]@{ PackageIdentifier = 'Microsoft.WindowsTerminal'; Version = '2.0' }
    )
}) }
$scopedInventory = ConvertTo-PcSetupWingetInventory -ExportObject $fakeExport -PackageIds @('Google.Chrome','Microsoft.WindowsTerminal') -WingetVersion 'v1' -ConfigSha256 ('A' * 64) -ProjectSha256 ('B' * 64) -InstallScopes @{ 'Google.Chrome' = 'machine'; 'Microsoft.WindowsTerminal' = 'user' }
Assert-True ($scopedInventory.InstallScope -eq 'per-package' -and ($scopedInventory.Packages | Where-Object PackageId -eq 'Google.Chrome').Scope -eq 'machine') 'O inventario deve registrar o escopo solicitado por pacote.'
Assert-True ($oneDisk.Packages.InstallScope -eq 'machine') 'O exemplo generico deve declarar o escopo de instalacao.'
Assert-True ($agentProfile.AiJail.Version -eq 'latest') 'ai-jail deve usar a release estavel atual por padrao.'
Assert-True ([string]::IsNullOrWhiteSpace([string]$agentProfile.AiJail.Sha256)) 'A politica latest nao pode fixar um hash antigo.'
Assert-True ($agentProfile.AiJail.RequireAssetDigest) 'A release atual deve exigir o digest publicado do asset.'

foreach ($capability in @('Network','PersistAgentState','Docker','SSH','Display','GPU','X11','HostSharedMemory','TerminalPassthrough','InheritEnvironment','UpdateCheck','Worktree','SystemdUser','Tailscale','Pictures')) {
    Assert-True ($configuration.Agent.Capabilities.ContainsKey($capability)) "Capacidade do agente ausente: $capability"
}

$releaseHelper = Get-Content -LiteralPath (Join-Path $root 'wsl\linux\github-release.sh') -Raw
$linuxBootstrap = Get-Content -LiteralPath (Join-Path $root 'wsl\linux\bootstrap.sh') -Raw
$linuxVerify = Get-Content -LiteralPath (Join-Path $root 'wsl\linux\verify.sh') -Raw
$agentLauncher = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-Agent.ps1') -Raw
$userPhase = Get-Content -LiteralPath (Join-Path $root 'scripts\90-user-profile.ps1') -Raw
$orchestrator = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-PcSetupUpdate.ps1') -Raw
$machineBootstrap = Get-Content -LiteralPath (Join-Path $root 'scripts\bootstrap.ps1') -Raw
$workflow = Get-Content -LiteralPath (Join-Path $root '.github\workflows\ci.yml') -Raw

Assert-True ($releaseHelper -match '/releases/latest' -and $releaseHelper -match '\.digest' -and $releaseHelper -match 'sha256:') 'A release atual deve ser resolvida com digest pela API do GitHub.'
Assert-True ($releaseHelper -match 'length == 1' -and $linuxBootstrap -match '--no-same-owner' -and $linuxBootstrap -match 'unsupported entry type') 'A release deve exigir um asset unico e extracao sem links ou metadados privilegiados.'
Assert-True ($linuxBootstrap -match 'ai_jail_binary_sha256' -and $linuxVerify -match 'sha256sum "\$binary"') 'Bootstrap e verify devem registrar e conferir o binario instalado.'
Assert-True ($linuxBootstrap -match 'sudo wheel docker lxd' -and $linuxVerify -match 'sudo\|wheel\|docker\|lxd') 'O agente nao pode permanecer em grupos privilegiados conhecidos.'
Assert-True ($agentLauncher -match '--no-inherit-env' -and $agentLauncher -match '--private-home' -and $agentLauncher -match '--landlock' -and $agentLauncher -match '--no-systemd-user') 'O launcher deve explicitar as fronteiras do sandbox.'
Assert-True ($agentLauncher -match 'readlink --canonicalize-existing') 'O workspace deve ser canonicalizado dentro do WSL.'
Assert-True ($userPhase -match 'Assert-PcSetupCompletedApplyReport' -and $userPhase -match '60-packages\.ps1' -and $userPhase -match '80-personalization\.ps1') 'A fase do usuario deve exigir a aplicacao protegida e executar pacotes e personalizacao.'
Assert-True ($orchestrator -match '\$isDailyUser' -and $orchestrator -match '\[TROCA DE CONTA\]' -and $orchestrator -match 'user-reconcile-completed\.json') 'A instalacao deve poder comecar em outra conta e concluir no perfil diario configurado.'
Assert-True ($machineBootstrap -notmatch "Name 'Pacotes'.+60-packages\.ps1.+Apply") 'Pacotes nao devem ser aplicados no contexto elevado da conta de recuperacao.'
Assert-True ((Test-Path -LiteralPath (Join-Path $root 'docs\RECUPERACAO.md')) -and (Test-Path -LiteralPath (Join-Path $root 'SECURITY.md'))) 'Documentos de recuperacao e seguranca devem existir.'
Assert-True ($workflow -match 'shellcheck' -and $workflow -match 'bash -n wsl/linux/github-release\.sh' -and $workflow -match 'timeout-minutes') 'A CI deve validar todos os scripts Bash com limite de tempo.'

$temporaryReport = Join-Path $env:TEMP ('pc-setup-test-report-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    $report = @{
        Status = 'Completed'; CompletedAt = (Get-Date).ToString('o')
        ConfigSha256 = (Get-FileHash -LiteralPath $configuration._ConfigPath -Algorithm SHA256).Hash
        ProjectSha256 = Get-PcSetupProjectFingerprint -Configuration $configuration
        Recovery = @{ Validated = $true; SequenceNumber = '1' }
    }
    Write-PcSetupJson -InputObject $report -Path $temporaryReport | Out-Null
    Assert-True ($null -ne (Assert-PcSetupCompletedApplyReport -Configuration $configuration -Path $temporaryReport)) 'A fase de usuario deve aceitar um comprovante atual e valido.'
    $report.CompletedAt = (Get-Date).AddHours(-25).ToString('o')
    Write-PcSetupJson -InputObject $report -Path $temporaryReport | Out-Null
    $staleRejected = $false
    try { Assert-PcSetupCompletedApplyReport -Configuration $configuration -Path $temporaryReport | Out-Null }
    catch { $staleRejected = $true }
    Assert-True $staleRejected 'A fase de usuario deve recusar comprovante antigo.'
}
finally {
    if (Test-Path -LiteralPath $temporaryReport) { Remove-Item -LiteralPath $temporaryReport -Force }
}

Write-Host 'PASS: objetivo de maquina pessoal, politicas atuais e fronteiras de seguranca.' -ForegroundColor Green
