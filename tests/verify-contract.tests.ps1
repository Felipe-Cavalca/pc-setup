#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
function Assert-Contains([string]$Content, [string]$Pattern, [string]$Message) {
    if ($Content -notmatch $Pattern) { throw $Message }
}

$verify = Get-Content -LiteralPath (Join-Path $root 'verify.ps1') -Raw
$bootstrap = Get-Content -LiteralPath (Join-Path $root 'bootstrap.ps1') -Raw
$packages = Get-Content -LiteralPath (Join-Path $root 'scripts\60-packages.ps1') -Raw

Assert-Contains $bootstrap 'Recovery\s+=\s+\$null' 'O relatorio base deve reservar o comprovante de recuperacao.'
Assert-Contains $bootstrap '\$baseReport\.Recovery\s*=' 'O Apply deve registrar o ponto de restauracao validado.'
Assert-Contains $verify 'Configuracao aplicada' 'O verify deve comparar a configuracao aplicada.'
Assert-Contains $verify 'Versao do projeto aplicada' 'O verify deve detectar mudanca do projeto apos o Apply.'
Assert-Contains $verify 'FileSystemRights\]\$grant\.Rights' 'O verify deve validar os direitos exatos das ACLs.'
Assert-Contains $verify 'controle total explicito e herdavel' 'O verify deve validar tambem as regras de SYSTEM e Administradores.'
Assert-Contains $verify 'Get-PcSetupWingetInstalledInventory' 'O verify deve consultar as versoes atuais do Winget.'
Assert-Contains $verify 'Inventario Winget/configuracao' 'O verify deve vincular o inventario a configuracao.'
Assert-Contains $verify 'Get-PcSetupWslDefaultUser' 'O verify deve conferir o usuario padrao do WSL.'
Assert-Contains $verify 'Plano de fundo/arquivo' 'O verify deve conferir a personalizacao prometida.'
Assert-Contains $packages 'winget-installed-' 'A etapa de pacotes deve arquivar inventarios JSON.'

Write-Host 'PASS: contrato ampliado do verificador.' -ForegroundColor Green
