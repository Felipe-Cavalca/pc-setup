#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Assert-True($Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}

$launcher = Get-Content -LiteralPath (Join-Path $root 'PERSONALIZAR.cmd') -Raw
$standalone = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-Personalization.ps1') -Raw
$personalization = Get-Content -LiteralPath (Join-Path $root 'scripts\80-personalization.ps1') -Raw
$machine = Get-Content -LiteralPath (Join-Path $root 'scripts\82-personalization-machine.ps1') -Raw
$profile = Get-Content -LiteralPath (Join-Path $root 'scripts\90-user-profile.ps1') -Raw
$update = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-PcSetupUpdate.ps1') -Raw
$configuration = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'config\machine.psd1')
$basePackages = Get-Content -LiteralPath (Join-Path $root 'config\packages\base.txt') -Raw

Assert-True ($launcher -match 'Start-Personalization\.ps1') 'PERSONALIZAR.cmd deve chamar o orquestrador independente.'
Assert-True ($standalone -match '-Plan' -and $standalone -match 'Read-Host.+Digite S' -and $standalone -match '-CreateRestorePoint -Apply') 'O launcher manual deve planejar, confirmar e criar o ponto antes da aplicacao.'
Assert-True ($standalone -match 'Start-Process[\s\S]+-Verb RunAs[\s\S]+-Wait') 'A fase de maquina deve solicitar elevacao e aguardar o resultado.'
Assert-True ($machine -match 'Start-PcSetupChangeSession' -and $machine -match 'AllowPinnedFolder\$folder') 'A fase elevada deve proteger e configurar os atalhos junto ao botao de energia.'
Assert-True ($personalization -match 'AppsUseLightTheme' -and $personalization -match 'SearchboxTaskbarMode' -and $personalization -match 'ShowTaskViewButton') 'Tema e barra de tarefas devem ser configurados no perfil diario.'
Assert-True ($machine -match "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge" -and $machine -match 'StartupBoostEnabled' -and $machine -match 'BackgroundModeEnabled') 'As politicas do Edge devem ser aplicadas pela fase elevada.'
Assert-True ($personalization -notmatch "HKCU:\\Software\\Policies\\Microsoft\\Edge" -and $personalization -match 'EdgeStartupEntriesRemoved') 'A fase diaria nao deve gravar em uma chave de politicas protegida.'
Assert-True ($personalization -match 'Microsoft\.OneDrive' -and $personalization -match 'Remove-AppxPackage') 'OneDrive e os Appx declarados devem possuir reconciliacao explicita.'
Assert-True ($personalization -match 'SHSetKnownFolderPath' -and $personalization -match 'robocopy\.exe' -and $personalization -notmatch '/MOVE') 'Pastas conhecidas devem ser redirecionadas depois de copia nao destrutiva.'
Assert-True ($personalization -match 'ArchiveSha256' -and $personalization -match 'Assets' -and $personalization -match 'start2\.bin') 'A limpeza dos fixados deve usar o layout da release validada por hash.'
Assert-True ($profile -match '\[switch\]\$IncludePersonalization' -and $profile -match '82-personalization-machine\.ps1' -and $profile -match '80-personalization\.ps1') 'A fase diaria deve incluir ambas as partes somente quando solicitado.'
Assert-True ($update -match 'Deseja reaplicar a personalizacao' -and $update -match 'LauncherName -eq ''INSTALAR\.cmd''' -and $update -match 'ApplyOnInstall') 'A instalacao deve aplicar o padrao e a atualizacao deve perguntar.'
Assert-True ($configuration.Personalization.Enabled -and $configuration.Personalization.Theme -eq 'Dark') 'O perfil padrao deve habilitar o tema escuro.'
Assert-True ($configuration.Personalization.HideTaskbarSearch -and $configuration.Personalization.HideTaskView -and $configuration.Personalization.ClearStartPins) 'O perfil padrao deve limpar pesquisa, Visao de Tarefas e fixados.'
Assert-True (@($configuration.Personalization.StartPowerMenuFolders).Count -eq 1 -and $configuration.Personalization.StartPowerMenuFolders[0] -eq 'Settings') 'Somente Configuracoes deve ficar junto ao botao de energia.'
Assert-True (@($configuration.Personalization.PreserveAppxPackages) -contains 'Microsoft.YourPhone' -and @($configuration.Personalization.PreserveAppxPackages) -contains 'MicrosoftWindows.CrossDevice') 'Vincular ao Celular e Cross Device devem ser preservados.'
Assert-True ($basePackages -match 'Proton\.ProtonMail\|user\|optional' -and $basePackages -match 'Proton\.ProtonVPN\|machine\|optional') 'Proton Mail e Proton VPN devem permanecer opcionais no Winget.'
Assert-True (Test-Path -LiteralPath (Join-Path $root 'docs\PERSONALIZACAO.md') -PathType Leaf) 'A personalizacao deve possuir documentacao propria.'

$plan = & (Join-Path $root 'scripts\80-personalization.ps1') -Config (Join-Path $root 'config\machine.psd1') -Plan
Assert-True ($plan.Action -eq 'Plan' -and @($plan.Actions).Count -ge 6) 'O modo Plan deve descrever as mudancas sem aplicar o Windows.'

Write-Host 'PASS: personalizacao integrada, manual, configuravel e nao destrutiva.' -ForegroundColor Green
