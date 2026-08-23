#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
function Assert-Contains([string]$Content, [string]$Pattern, [string]$Message) {
    if ($Content -notmatch $Pattern) { throw $Message }
}

$verify = Get-Content -LiteralPath (Join-Path $root 'verify.ps1') -Raw
$bootstrap = Get-Content -LiteralPath (Join-Path $root 'bootstrap.ps1') -Raw
$packages = Get-Content -LiteralPath (Join-Path $root 'scripts\60-packages.ps1') -Raw
$personalization = Get-Content -LiteralPath (Join-Path $root 'scripts\80-personalization.ps1') -Raw

Assert-Contains $bootstrap 'Recovery\s+=\s+\$null' 'O relatorio base deve reservar o comprovante de recuperacao.'
Assert-Contains $bootstrap '\$baseReport\.Recovery\s*=' 'O Apply deve registrar o ponto de restauracao validado.'
Assert-Contains $verify 'Configuracao aplicada' 'O verify deve comparar a configuracao aplicada.'
Assert-Contains $verify 'Versao do projeto aplicada' 'O verify deve detectar mudanca do projeto apos o Apply.'
Assert-Contains $verify 'FileSystemRights\]\$grant\.Rights' 'O verify deve validar os direitos exatos das ACLs.'
Assert-Contains $verify 'controle total explicito e herdavel' 'O verify deve validar tambem as regras de SYSTEM e Administradores.'
Assert-Contains $verify "Name 'Pacotes Winget'.+fase da conta diaria" 'O verify de maquina deve encaminhar a validacao Winget para a fase correta.'
Assert-Contains $verify 'Get-PcSetupWslDefaultUser' 'O verify deve conferir o usuario padrao do WSL.'
Assert-Contains $verify 'HyperVAdministratorAccounts' 'O verify deve conferir quem administra o Hyper-V.'
Assert-Contains $verify 'Get-PcSetupExpectedWslDefaultUser' 'O verify deve preservar o usuario padrao ao validar Agent.'
Assert-Contains $verify "Name 'Personalizacao'.+fase da conta diaria" 'O verify de maquina deve encaminhar a personalizacao para a fase correta.'
Assert-Contains $personalization 'Assert-PcSetupCompletedApplyReport' 'A personalizacao deve exigir o comprovante protegido da mesma aplicacao.'
Assert-Contains $personalization 'HKCU:\\Control Panel\\Desktop' 'A fase da conta diaria deve conferir o registro do plano de fundo.'
Assert-Contains $personalization 'Get-FileHash.+sourcePath.+Get-FileHash.+targetPath' 'A fase da conta diaria deve validar a copia local do plano de fundo.'
Assert-Contains $packages 'Assert-PcSetupCompletedApplyReport' 'A etapa Winget deve exigir o comprovante protegido da mesma aplicacao.'
Assert-Contains $packages 'Get-PcSetupWingetInstalledInventory' 'A etapa de usuario deve consultar e validar as versoes atuais do Winget.'
Assert-Contains $packages 'ConfigSha256.*ProjectSha256' 'O inventario Winget deve ser vinculado a configuracao e ao projeto aplicados.'
Assert-Contains $packages 'winget-installed-' 'A etapa de pacotes deve arquivar inventarios JSON.'

Write-Host 'PASS: contrato ampliado do verificador.' -ForegroundColor Green
