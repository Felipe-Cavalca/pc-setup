#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
function Assert-Contains([string]$Content, [string]$Pattern, [string]$Message) {
    if ($Content -notmatch $Pattern) { throw $Message }
}

$verify = Get-Content -LiteralPath (Join-Path $root 'scripts\verify.ps1') -Raw
$bootstrap = Get-Content -LiteralPath (Join-Path $root 'scripts\bootstrap.ps1') -Raw
$packages = Get-Content -LiteralPath (Join-Path $root 'scripts\60-packages.ps1') -Raw
$personalization = Get-Content -LiteralPath (Join-Path $root 'scripts\80-personalization.ps1') -Raw

Assert-Contains $bootstrap 'Recovery\s+=\s+\$null' 'O relatorio base deve reservar o comprovante de recuperacao.'
Assert-Contains $bootstrap '\$baseReport\.Recovery\s*=' 'O Apply deve registrar o ponto de restauracao validado.'
Assert-Contains $verify 'Configuracao aplicada' 'O verify deve comparar a configuracao aplicada.'
Assert-Contains $verify '\[switch\]\$PassThru' 'O verify deve permitir que o launcher elevado preserve e classifique o resultado.'
Assert-Contains $verify 'Versao do projeto aplicada' 'O verify deve detectar mudanca do projeto apos o Apply.'
Assert-Contains $verify 'FileSystemRights\]\$grant\.Rights' 'O verify deve validar os direitos exatos das ACLs.'
Assert-Contains $verify 'allowedRights.+FileSystemRights\]::Synchronize' 'O verify deve aceitar apenas o bit Synchronize acrescentado canonicamente pelo Windows.'
Assert-Contains $verify 'hasRequiredRights[\s\S]+hasOnlyAllowedRights' 'O verify deve exigir os direitos configurados sem aceitar privilegios adicionais.'
Assert-Contains $verify 'controle total explicito e herdavel' 'O verify deve validar tambem as regras de SYSTEM e Administradores.'
Assert-Contains $verify "Name 'Pacotes Winget'.+fase da conta diaria" 'O verify de maquina deve encaminhar a validacao Winget para a fase correta.'
Assert-Contains $verify 'Get-PcSetupWslDefaultUser' 'O verify deve conferir o usuario padrao do WSL.'
Assert-Contains $verify 'HyperVAdministratorAccounts' 'O verify deve conferir quem administra o Hyper-V.'
Assert-Contains $verify 'Armazenamento Hyper-V' 'O verify deve conferir os destinos configurados no Hyper-V.'
Assert-Contains $verify 'Test-PcSetupBackupManifest' 'O verify deve validar o snapshot local quando ele existir.'
Assert-Contains $verify 'Versoes conhecidas' 'O verify da conta diaria deve conferir o snapshot conhecido como bom.'
Assert-Contains $verify "Name 'Pesquisa web do Windows'" 'O verify deve conferir as politicas de pesquisa web aplicadas na maquina.'
Assert-Contains $verify 'Get-PcSetupExpectedWslDefaultUser' 'O verify deve preservar o usuario padrao ao validar Agent.'
Assert-Contains $verify "Name 'Personalizacao do perfil'.+fase da conta diaria" 'O verify de maquina deve encaminhar a personalizacao do perfil para a fase correta.'
Assert-Contains $personalization 'Assert-PcSetupCompletedApplyReport' 'A personalizacao deve exigir o comprovante protegido da mesma aplicacao.'
Assert-Contains $personalization 'HKCU:\\Control Panel\\Desktop' 'A fase da conta diaria deve conferir o registro do plano de fundo.'
Assert-Contains $personalization 'Get-FileHash[^\r\n]+wallpaperSource[\s\S]+Get-FileHash[^\r\n]+wallpaperTarget' 'A fase da conta diaria deve validar a copia local do plano de fundo.'
Assert-Contains $packages 'Assert-PcSetupCompletedApplyReport' 'A etapa Winget deve exigir o comprovante protegido da mesma aplicacao.'
Assert-Contains $packages 'Get-PcSetupWingetInstalledInventory' 'A etapa de usuario deve consultar e validar as versoes atuais do Winget.'
Assert-Contains $packages 'ConfigSha256.*ProjectSha256' 'O inventario Winget deve ser vinculado a configuracao e ao projeto aplicados.'
Assert-Contains $packages 'winget-installed-' 'A etapa de pacotes deve arquivar inventarios JSON.'
Assert-Contains $packages "Versions.Mode -eq 'Locked'" 'A etapa de pacotes deve validar divergencias no modo de versoes fixadas.'

Write-Host 'PASS: contrato ampliado do verificador.' -ForegroundColor Green
