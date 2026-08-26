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
$systemPersonalization = Get-Content -LiteralPath (Join-Path $root 'scripts\Invoke-PcSetupSystemPersonalization.ps1') -Raw
$profile = Get-Content -LiteralPath (Join-Path $root 'scripts\90-user-profile.ps1') -Raw
$update = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-PcSetupUpdate.ps1') -Raw
$configuration = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'config\machine.psd1')
$basePackages = Get-Content -LiteralPath (Join-Path $root 'config\packages\base.txt') -Raw

Assert-True ($launcher -match 'Start-Personalization\.ps1') 'PERSONALIZAR.cmd deve chamar o orquestrador independente.'
Assert-True ($standalone -match '-Plan' -and $standalone -match 'Read-Host.+Digite S' -and $standalone -match '-CreateRestorePoint -Apply') 'O launcher manual deve planejar, confirmar e criar o ponto antes da aplicacao.'
Assert-True ($standalone -match 'Start-Process[\s\S]+-Verb RunAs[\s\S]+-Wait') 'A fase de maquina deve solicitar elevacao e aguardar o resultado.'
Assert-True ($machine -match 'Start-PcSetupChangeSession' -and $machine -match 'New-ScheduledTaskPrincipal' -and $machine -match "UserId 'SYSTEM'") 'A fase elevada deve proteger e delegar os CSPs de sistema ao LocalSystem.'
Assert-True ($systemPersonalization -match 'MDM_Policy_Config01_Start02' -and $systemPersonalization -match 'AllowPinnedFolder\$folder') 'O provedor oficial deve configurar os atalhos junto ao botao de energia.'
Assert-True ($systemPersonalization -match 'MDM_Policy_User_Config01_Start02' -and $systemPersonalization -match 'PinGeneration' -and $systemPersonalization -match 'PinListPlacement') 'A barra deve usar XML oficial, substituicao dos fixados e geracao editavel.'
Assert-True ($personalization -match 'AppsUseLightTheme' -and $personalization -match 'SearchboxTaskbarMode' -and $personalization -match 'ShowTaskViewButton') 'Tema e barra de tarefas devem ser configurados no perfil diario.'
Assert-True ($machine -match "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge" -and $machine -match 'StartupBoostEnabled' -and $machine -match 'BackgroundModeEnabled') 'As politicas do Edge devem ser aplicadas pela fase elevada.'
Assert-True ($personalization -notmatch "HKCU:\\Software\\Policies\\Microsoft\\Edge" -and $personalization -match 'EdgeStartupEntriesRemoved') 'A fase diaria nao deve gravar em uma chave de politicas protegida.'
Assert-True ($configuration.Personalization.DisableWebSearch) 'A pesquisa web deve ficar desabilitada no perfil padrao.'
Assert-True ($machine -match 'Windows Search' -and $machine -match 'DisableWebSearch' -and $machine -match 'ConnectedSearchUseWeb' -and $machine -match 'EnableDynamicContentInWSB') 'A fase administrativa deve aplicar as politicas de pesquisa web e destaques da maquina.'
Assert-True ($machine -match 'HKEY_USERS' -and $machine -match 'DisableSearchBoxSuggestions' -and $personalization -match 'BingSearchEnabled') 'O modo agressivo deve aplicar as configuracoes protegidas pela fase elevada e as configuracoes comuns pela conta diaria.'
Assert-True ($personalization -notmatch 'HKCU:\\Software\\Policies') 'A fase diaria nao deve gravar politicas protegidas.'
Assert-True ($personalization -match 'Microsoft\.OneDrive' -and $personalization -match 'Remove-AppxPackage') 'OneDrive e os Appx declarados devem possuir reconciliacao explicita.'
Assert-True ($machine -match 'Get-AppxPackage -AllUsers' -and $machine -match 'Remove-AppxProvisionedPackage' -and $machine -match 'Remove-AppxPackage.+-AllUsers') 'Outlook e LinkedIn devem ser removidos dos usuarios e do provisionamento.'
Assert-True ($personalization -match 'SHSetKnownFolderPath' -and $personalization -match 'robocopy\.exe' -and $personalization -notmatch '/MOVE') 'Pastas conhecidas devem ser redirecionadas depois de copia nao destrutiva.'
Assert-True ($personalization -match 'KnownFoldersRestoredToWindowsProfile' -and $personalization -match 'Join-Path \$env:USERPROFILE \$folderName') 'A configuracao deve restaurar pastas conhecidas para o perfil original.'
Assert-True ($personalization -match 'New-Item -ItemType Junction' -and $personalization -match 'ProfileLink') 'A pasta Data deve ser criada como juncao idempotente para o perfil original.'
Assert-True ($personalization -match 'HKCU:\\Software\\Google\\DriveFS' -and $personalization -match 'DefaultMountPoint') 'O Google Drive deve receber o ponto de montagem streaming no perfil diario.'
Assert-True ($personalization -match 'ArchiveSha256' -and $personalization -match 'Assets' -and $personalization -match 'start2\.bin') 'A limpeza dos fixados deve usar o layout da release validada por hash.'
Assert-True ($personalization -match 'StartMenuExperienceHost' -and $personalization -match 'LockScreenPreparedForManualSelection' -and $personalization -match 'ms-settings:lockscreen') 'O menu Iniciar deve recarregar e a tela de bloqueio deve possuir orientacao manual configurada.'
Assert-True ($profile -match '\[switch\]\$IncludePersonalization' -and $profile -match '82-personalization-machine\.ps1' -and $profile -match '80-personalization\.ps1') 'A fase diaria deve incluir ambas as partes somente quando solicitado.'
Assert-True ($update -match 'Deseja reaplicar a personalizacao' -and $update -match 'LauncherName -eq ''INSTALAR\.cmd''' -and $update -match 'ApplyOnInstall') 'A instalacao deve aplicar o padrao e a atualizacao deve perguntar.'
Assert-True ($configuration.Personalization.Enabled -and $configuration.Personalization.Theme -eq 'Dark') 'O perfil padrao deve habilitar o tema escuro.'
Assert-True ($configuration.Personalization.HideTaskbarSearch -and $configuration.Personalization.HideTaskView -and $configuration.Personalization.ClearStartPins) 'O perfil padrao deve limpar pesquisa, Visao de Tarefas e fixados.'
Assert-True (@($configuration.Personalization.StartPowerMenuFolders).Count -eq 1 -and $configuration.Personalization.StartPowerMenuFolders[0] -eq 'Settings') 'Somente Configuracoes deve ficar junto ao botao de energia.'
Assert-True ($configuration.Personalization.WebSearchMode -eq 'Aggressive') 'O perfil pessoal deve usar o modo agressivo de pesquisa web.'
Assert-True ($configuration.Personalization.Taskbar.Enabled -and $configuration.Personalization.Taskbar.ReplaceDefaultPins -and @($configuration.Personalization.Taskbar.Pins).Count -eq 6) 'A barra deve substituir os fixados padrao por seis itens configuraveis.'
Assert-True (@($configuration.Personalization.RemoveAppxPackages) -contains 'Microsoft.OutlookForWindows' -and @($configuration.Personalization.RemoveAppxPackages) -contains '7EE7776C.LinkedInforWindows') 'Outlook e LinkedIn devem estar declarados com nomes exatos.'
Assert-True (@($configuration.Personalization.PreserveAppxPackages) -contains 'Microsoft.YourPhone' -and @($configuration.Personalization.PreserveAppxPackages) -contains 'MicrosoftWindows.CrossDevice') 'Vincular ao Celular e Cross Device devem ser preservados.'
Assert-True (-not $configuration.Personalization.RedirectKnownFolders -and $configuration.Personalization.RestoreKnownFoldersToProfile) 'Pastas pessoais devem permanecer no perfil Windows por padrao.'
Assert-True ($configuration.Personalization.ProfileLink.Enabled -and $configuration.Personalization.ProfileLink.Name -eq 'Data') 'A juncao Data deve estar habilitada por padrao.'
Assert-True ($configuration.Personalization.GoogleDrive.Enabled -and $configuration.Personalization.GoogleDrive.Mode -eq 'Streaming') 'Google Drive deve usar streaming por padrao.'
Assert-True ($configuration.Personalization.LockScreen.Enabled -and $configuration.Personalization.LockScreen.Mode -eq 'Manual' -and $configuration.Personalization.LockScreen.Status -eq 'None') 'A tela de bloqueio deve preparar a imagem sem impedir alteracoes posteriores.'
Assert-True ($basePackages -match 'Proton\.ProtonMail\|user\|optional' -and $basePackages -match 'Proton\.ProtonVPN\|machine\|optional') 'Proton Mail e Proton VPN devem permanecer opcionais no Winget.'
Assert-True (Test-Path -LiteralPath (Join-Path $root 'docs\PERSONALIZACAO.md') -PathType Leaf) 'A personalizacao deve possuir documentacao propria.'

$tokens = $null
$parseErrors = $null
$systemAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts\Invoke-PcSetupSystemPersonalization.ps1'), [ref]$tokens, [ref]$parseErrors)
$xmlFunction = $systemAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'ConvertTo-PcSetupTaskbarXml' }, $true)
Invoke-Expression ('function ConvertTo-PcSetupTaskbarXml ' + $xmlFunction.Body.Extent.Text)
[xml]$taskbarXml = ConvertTo-PcSetupTaskbarXml -Taskbar $configuration.Personalization.Taskbar
$taskbarCollection = $taskbarXml.LayoutModificationTemplate.CustomTaskbarLayoutCollection
$taskbarPins = @($taskbarCollection.TaskbarLayout.TaskbarPinList.ChildNodes)
Assert-True ($taskbarCollection.PinListPlacement -eq 'Replace' -and $taskbarPins.Count -eq 6) 'O XML deve substituir os fixados padrao pelos seis itens configurados.'
Assert-True (@($taskbarPins | Where-Object PinGeneration -ne '1').Count -eq 0) 'Todos os fixados devem permitir remocao persistente pela geracao configurada.'

$plan = & (Join-Path $root 'scripts\80-personalization.ps1') -Config (Join-Path $root 'config\machine.psd1') -Plan
Assert-True ($plan.Action -eq 'Plan' -and @($plan.Actions).Count -ge 6) 'O modo Plan deve descrever as mudancas sem aplicar o Windows.'

Write-Host 'PASS: personalizacao integrada, manual, configuravel e nao destrutiva.' -ForegroundColor Green
