#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [string]$WindowsApplyReport = '',
    [string]$DataRoot = '',
    [switch]$Plan,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\machine.psd1' }
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1') -Force

function Set-PcSetupDword {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][int]$Value)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Initialize-PcSetupKnownFolderApi {
    if ('PcSetup.PersonalizationNativeMethods' -as [type]) { return }
    Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace PcSetup {
    public static class PersonalizationNativeMethods {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        public static extern int SHGetKnownFolderPath(ref Guid rfid, uint flags, IntPtr token, out IntPtr path);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        public static extern int SHSetKnownFolderPath(ref Guid rfid, uint flags, IntPtr token, string path);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool SystemParametersInfo(int action, int parameter, string value, int flags);
    }
}
'@
}

function Get-PcSetupKnownFolderIds {
    return @{
        Desktop   = [guid]'B4BFCC3A-DB2C-424C-B029-7FE99A87C641'
        Documents = [guid]'FDD39AD0-238F-46AF-ADB4-6C85480369C7'
        Downloads = [guid]'374DE290-123F-4565-9164-39C4925E467B'
        Music     = [guid]'4BD8D571-6D19-48D3-BE97-422220080E43'
        Pictures  = [guid]'33E28130-4E1E-4676-835A-98395C3BC3BB'
        Videos    = [guid]'18989B1D-99B5-455B-841C-AB7C74E4DDFC'
    }
}

function Get-PcSetupKnownFolderPath {
    param([Parameter(Mandatory)][guid]$Id)
    Initialize-PcSetupKnownFolderApi
    $pointer = [IntPtr]::Zero
    $folderId = $Id
    $result = [PcSetup.PersonalizationNativeMethods]::SHGetKnownFolderPath([ref]$folderId, 0, [IntPtr]::Zero, [ref]$pointer)
    if ($result -ne 0) { throw ('SHGetKnownFolderPath falhou com HRESULT 0x{0:X8}.' -f ($result -band 0xffffffffL)) }
    try { return [Runtime.InteropServices.Marshal]::PtrToStringUni($pointer) }
    finally { if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeCoTaskMem($pointer) } }
}

function Set-PcSetupKnownFolderPath {
    param([Parameter(Mandatory)][guid]$Id, [Parameter(Mandatory)][string]$Path)
    Initialize-PcSetupKnownFolderApi
    $folderId = $Id
    $result = [PcSetup.PersonalizationNativeMethods]::SHSetKnownFolderPath([ref]$folderId, 0, [IntPtr]::Zero, $Path)
    if ($result -ne 0) { throw ('SHSetKnownFolderPath falhou para {0} com HRESULT 0x{1:X8}.' -f $Path, ($result -band 0xffffffffL)) }
}

function Copy-PcSetupKnownFolderContent {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { return }
    if ([IO.Path]::GetFullPath($Source).TrimEnd('\') -eq [IO.Path]::GetFullPath($Destination).TrimEnd('\')) { return }
    & robocopy.exe $Source $Destination /E /COPY:DAT /DCOPY:DAT /XJ /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Host
    $exitCode = $LASTEXITCODE
    if ($exitCode -gt 7) { throw "Nao foi possivel copiar o conteudo de $Source para $Destination. Robocopy: $exitCode." }
}

function Set-PcSetupProfileJunction {
    param(
        [Parameter(Mandatory)][string]$ParentPath,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$TargetPath
    )

    $linkPath = [IO.Path]::GetFullPath((Join-Path $ParentPath $Name))
    $expectedTarget = [IO.Path]::GetFullPath($TargetPath).TrimEnd('\')
    if (Test-Path -LiteralPath $linkPath) {
        $item = Get-Item -LiteralPath $linkPath -Force
        $actualTarget = @($item.Target) | Select-Object -First 1
        $isJunction = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -and [string]$item.LinkType -eq 'Junction'
        if (-not $isJunction -or [string]::IsNullOrWhiteSpace([string]$actualTarget) -or [IO.Path]::GetFullPath([string]$actualTarget).TrimEnd('\') -ne $expectedTarget) {
            throw "O caminho $linkPath ja existe e nao e a juncao esperada para $expectedTarget. Ele nao foi alterado nem removido."
        }
        return [pscustomobject]@{ Path = $linkPath; Target = $expectedTarget; Action = 'AlreadyConfigured' }
    }

    if (-not (Test-Path -LiteralPath $ParentPath -PathType Container)) { throw "A pasta do usuario nos dados ainda nao existe: $ParentPath" }
    New-Item -ItemType Junction -Path $linkPath -Target $expectedTarget -ErrorAction Stop | Out-Null
    $created = Get-Item -LiteralPath $linkPath -Force
    $createdTarget = @($created.Target) | Select-Object -First 1
    if ([string]$created.LinkType -ne 'Junction' -or [IO.Path]::GetFullPath([string]$createdTarget).TrimEnd('\') -ne $expectedTarget) {
        throw "A juncao criada em $linkPath nao aponta para $expectedTarget."
    }
    return [pscustomobject]@{ Path = $linkPath; Target = $expectedTarget; Action = 'Created' }
}

function Set-PcSetupGoogleDriveStreamingMountPoint {
    param([Parameter(Mandatory)][string]$Path)

    $mountPoint = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $mountPoint -PathType Container)) { throw "A pasta do Google Drive ainda nao existe: $mountPoint" }
    $registryPath = 'HKCU:\Software\Google\DriveFS'
    $current = $null
    if (Test-Path -LiteralPath $registryPath) {
        $current = Get-ItemPropertyValue -LiteralPath $registryPath -Name 'DefaultMountPoint' -ErrorAction SilentlyContinue
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$current) -and [IO.Path]::GetFullPath([string]$current).TrimEnd('\') -eq $mountPoint) {
        return [pscustomobject]@{ Path = $mountPoint; RegistryPath = $registryPath; Action = 'AlreadyConfigured' }
    }
    if (Get-ChildItem -LiteralPath $mountPoint -Force -ErrorAction Stop | Select-Object -First 1) {
        throw "O Google Drive exige um ponto de montagem vazio. Revise manualmente o conteudo de $mountPoint; nada foi removido."
    }
    if (-not (Test-Path -LiteralPath $registryPath)) { New-Item -Path $registryPath -Force | Out-Null }
    New-ItemProperty -LiteralPath $registryPath -Name 'DefaultMountPoint' -PropertyType String -Value $mountPoint -Force | Out-Null
    $confirmed = [string](Get-ItemPropertyValue -LiteralPath $registryPath -Name 'DefaultMountPoint' -ErrorAction Stop)
    if ([IO.Path]::GetFullPath($confirmed).TrimEnd('\') -ne $mountPoint) { throw 'O ponto de montagem do Google Drive nao foi confirmado no perfil atual.' }
    return [pscustomobject]@{ Path = $mountPoint; RegistryPath = $registryPath; Action = 'Configured' }
}

function Get-PcSetupEmptyStartAsset {
    param([Parameter(Mandatory)][hashtable]$Configuration, [Parameter(Mandatory)][string]$StateRoot)

    $release = [string]$Configuration.Debloat.Release
    $expectedArchiveHash = ([string]$Configuration.Debloat.ArchiveSha256).ToUpperInvariant()
    $assetDirectory = Join-Path $StateRoot 'assets'
    $assetPath = Join-Path $assetDirectory "win11debloat-$release-empty-start2.bin"
    $metadataPath = "$assetPath.json"
    New-Item -ItemType Directory -Path $assetDirectory -Force | Out-Null

    if ((Test-Path -LiteralPath $assetPath -PathType Leaf) -and (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        try {
            $metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $assetHash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash
            if ($metadata.Release -eq $release -and $metadata.ArchiveSha256 -eq $expectedArchiveHash -and $metadata.AssetSha256 -eq $assetHash) {
                return $assetPath
            }
        }
        catch { }
    }

    $workRoot = Join-Path $env:TEMP ("pc-setup-start-layout-" + [guid]::NewGuid().ToString('N'))
    $zipPath = "$workRoot.zip"
    $url = "https://github.com/$($Configuration.Debloat.Repository)/archive/refs/tags/$release.zip"
    try {
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
        $archiveHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
        if ($archiveHash -ne $expectedArchiveHash) { throw 'O SHA-256 do Win11Debloat diverge do valor revisado.' }
        Expand-Archive -LiteralPath $zipPath -DestinationPath $workRoot -Force
        $sourceAsset = Get-ChildItem -LiteralPath $workRoot -Recurse -Filter 'start2.bin' -File |
            Where-Object { $_.FullName -match '[\\/]Assets[\\/]Start[\\/]start2\.bin$' } |
            Select-Object -First 1
        if (-not $sourceAsset) { throw 'O layout vazio do menu Iniciar nao foi encontrado no arquivo validado.' }
        Copy-Item -LiteralPath $sourceAsset.FullName -Destination $assetPath -Force
        $metadata = [ordered]@{
            Release       = $release
            ArchiveSha256 = $archiveHash
            AssetSha256   = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash
            CachedAt      = (Get-Date).ToString('o')
        }
        Write-PcSetupJson -InputObject $metadata -Path $metadataPath | Out-Null
        return $assetPath
    }
    finally {
        if (Test-Path -LiteralPath $workRoot) { Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue }
    }
}

function Remove-PcSetupConfiguredAppxPackages {
    param([Parameter(Mandatory)][string[]]$Patterns)
    $removed = @()
    foreach ($pattern in $Patterns) {
        $packages = @(Get-AppxPackage -ErrorAction Stop | Where-Object { $_.Name -like $pattern -or $_.PackageFullName -like $pattern })
        foreach ($package in $packages) {
            Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
            $removed += [string]$package.Name
        }
    }
    return @($removed | Select-Object -Unique)
}

function Remove-PcSetupOneDrive {
    $wingetResult = 'Unavailable'
    $uninstallSucceeded = $false
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        & $winget.Source uninstall --id Microsoft.OneDrive --exact --silent --disable-interactivity --accept-source-agreements
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            $wingetResult = 'Uninstalled'
            $uninstallSucceeded = $true
        }
        elseif ($exitCode -eq -1978335212) {
            $wingetResult = 'AlreadyAbsent'
            $uninstallSucceeded = $true
        }
        else {
            $wingetResult = "Failed:$exitCode"
            Write-Warning "Winget nao removeu o OneDrive (codigo $exitCode); tentando o desinstalador local."
        }
    }

    if (-not $uninstallSucceeded) {
        $setupCandidates = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\Update\OneDriveSetup.exe'),
            (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'),
            (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
        )
        $setup = $setupCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if ($setup) {
            $process = Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait -PassThru
            if ($process.ExitCode -ne 0) { throw "O desinstalador local do OneDrive terminou com codigo $($process.ExitCode)." }
            $uninstallSucceeded = $true
            $wingetResult = 'LocalUninstaller'
        }
    }

    Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    if (-not $uninstallSucceeded) { throw "Nao foi possivel remover o OneDrive. Resultado Winget: $wingetResult." }
    return $wingetResult
}

$mode = Get-PcSetupExecutionMode -Plan:$Plan -Apply:$Apply
$configuration = Import-PcSetupConfiguration -Path $Config
$personalization = $configuration.Personalization
if (-not $personalization.Enabled) {
    Write-Host '[IGNORADO] Personalizacao desabilitada.'
    return [pscustomobject]@{ Step = 'Personalization'; Mode = $mode; Enabled = $false; Action = 'None' }
}

$wallpaperSource = $null
if (-not [string]::IsNullOrWhiteSpace([string]$personalization.WallpaperPath)) {
    $wallpaperSource = Resolve-PcSetupProjectPath -Configuration $configuration -Value ([string]$personalization.WallpaperPath) -SettingName 'Personalization.WallpaperPath'
    if (-not (Test-Path -LiteralPath $wallpaperSource -PathType Leaf)) { throw "Arquivo de plano de fundo ausente: $wallpaperSource" }
}

$planActions = @(
    "Tema $($personalization.Theme)",
    'Configurar barra de tarefas e menu Iniciar',
    "Mostrar junto ao botao de energia somente: $(@($personalization.StartPowerMenuFolders) -join ', ')",
    'Impedir Edge em segundo plano e na inicializacao',
    'Remover OneDrive e pacotes Appx configurados',
    'Preservar Vincular ao Celular e Cross Device'
)
if ($personalization.DisableWebSearch) { $planActions += 'Remover consultas, resultados e destaques da web da pesquisa do Windows' }
if ($personalization.RedirectKnownFolders) { $planActions += "Redirecionar pastas pessoais para Storage.Paths.$($personalization.KnownFoldersPathKey), copiando o conteudo sem apagar a origem" }
if ($personalization.RestoreKnownFoldersToProfile) { $planActions += 'Restaurar as pastas pessoais para o perfil padrao do Windows, copiando o conteudo sem apagar a origem antiga' }
if ($personalization.ProfileLink.Enabled) { $planActions += "Criar a juncao $($personalization.ProfileLink.Name) para o perfil original do Windows" }
if ($personalization.GoogleDrive.Enabled) { $planActions += "Configurar Google Drive em streaming usando Storage.Paths.$($personalization.GoogleDrive.PathKey)" }
if ($wallpaperSource) { $planActions += "Aplicar plano de fundo: $wallpaperSource" }
if ($mode -eq 'Plan') {
    foreach ($action in $planActions) { Write-Host "[PLANO] $action" }
    return [pscustomobject]@{ Step = 'Personalization'; Mode = $mode; Enabled = $true; Actions = $planActions; Action = 'Plan' }
}

if ($env:USERNAME -ne [string]$configuration.Accounts.DailyUser.Name) {
    throw "A personalizacao deve ser aplicada na sessao da conta diaria $($configuration.Accounts.DailyUser.Name). Usuario atual: $env:USERNAME."
}

$applyReport = $null
if (-not [string]::IsNullOrWhiteSpace($WindowsApplyReport)) {
    $applyReport = Assert-PcSetupCompletedApplyReport -Configuration $configuration -Path $WindowsApplyReport
    $DataRoot = [string]$applyReport.Storage.DataRoot
}
if ([string]::IsNullOrWhiteSpace($DataRoot)) { throw 'A personalizacao exige a raiz de dados comprovada pela instalacao ou pelo launcher manual.' }
$storage = @{ SystemRoot = [IO.Path]::GetPathRoot($env:SystemRoot); DataRoot = [IO.Path]::GetFullPath($DataRoot) }
$configuredPaths = Get-PcSetupConfiguredPaths -Configuration $configuration -Storage $storage
$knownFolderRoot = if ($personalization.RedirectKnownFolders) { [string]$configuredPaths[[string]$personalization.KnownFoldersPathKey] } else { $null }
if ($personalization.RedirectKnownFolders -and -not (Test-Path -LiteralPath $knownFolderRoot -PathType Container)) {
    throw "A pasta de dados configurada ainda nao existe: $knownFolderRoot. Execute INSTALAR.cmd antes da personalizacao manual."
}

$stateRoot = Get-PcSetupRuntimePath -Configuration $configuration -Key 'UserStateDirectory'
$actions = @()
$currentBuild = [int](Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction Stop)

$themePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$lightThemeValue = if ($personalization.Theme -eq 'Dark') { 0 } else { 1 }
Set-PcSetupDword -Path $themePath -Name 'AppsUseLightTheme' -Value $lightThemeValue
Set-PcSetupDword -Path $themePath -Name 'SystemUsesLightTheme' -Value $lightThemeValue
$actions += "Theme:$($personalization.Theme)"

Set-PcSetupDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Value $(if ($personalization.HideTaskbarSearch) { 0 } else { 2 })
Set-PcSetupDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowTaskViewButton' -Value $(if ($personalization.HideTaskView) { 0 } else { 1 })
$actions += 'Taskbar'

$allAppsViewMode = @{ Category = 0; Grid = 1; List = 2 }[[string]$personalization.StartAllAppsView]
Set-PcSetupDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Start' -Name 'AllAppsViewMode' -Value $allAppsViewMode
if ($currentBuild -lt 26200) {
    Write-Warning "A build $currentBuild ainda pode ignorar StartAllAppsView=$($personalization.StartAllAppsView); a configuracao foi registrada para uma atualizacao futura."
    $actions += 'StartAllAppsPendingWindowsUpdate'
}
if ($personalization.ClearStartPins -and $currentBuild -ge 22621) {
    $emptyStartAsset = Get-PcSetupEmptyStartAsset -Configuration $configuration -StateRoot $stateRoot
    $startStateDirectory = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState'
    New-Item -ItemType Directory -Path $startStateDirectory -Force | Out-Null
    $startStatePath = Join-Path $startStateDirectory 'start2.bin'
    if (Test-Path -LiteralPath $startStatePath -PathType Leaf) {
        $backupDirectory = Join-Path $stateRoot 'backups\start-menu'
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        Copy-Item -LiteralPath $startStatePath -Destination (Join-Path $backupDirectory ("start2-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bin.bkp')) -Force
    }
    Copy-Item -LiteralPath $emptyStartAsset -Destination $startStatePath -Force
    if ((Get-FileHash -LiteralPath $emptyStartAsset -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $startStatePath -Algorithm SHA256).Hash) {
        throw 'O menu Iniciar nao confirmou a copia do layout vazio.'
    }
    $actions += 'StartPinsCleared'
}
elseif ($personalization.ClearStartPins) {
    Write-Warning "A limpeza automatica dos fixados exige Windows build 22621 ou posterior. Build atual: $currentBuild."
    $actions += 'StartPinsPendingWindowsUpdate'
}
$actions += "StartAllApps:$($personalization.StartAllAppsView)"

if ($personalization.DisableEdgeBackground) {
    $edgeRunPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (Test-Path -LiteralPath $edgeRunPath) {
        $runValues = Get-ItemProperty -LiteralPath $edgeRunPath
        foreach ($property in @($runValues.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and ($_.Name -match 'Edge|msedge' -or [string]$_.Value -match 'msedge\.exe') })) {
            Remove-ItemProperty -LiteralPath $edgeRunPath -Name $property.Name -Force
        }
    }
    $actions += 'EdgeStartupEntriesRemoved'
}

if ($personalization.RemoveOneDrive) {
    $oneDriveResult = Remove-PcSetupOneDrive
    foreach ($namespacePath in @(
        'HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}',
        'HKCU:\Software\Classes\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
    )) { Set-PcSetupDword -Path $namespacePath -Name 'System.IsPinnedToNameSpaceTree' -Value 0 }
    $actions += "OneDrive:$oneDriveResult"
}

$removedAppx = Remove-PcSetupConfiguredAppxPackages -Patterns @($personalization.RemoveAppxPackages)
foreach ($pattern in @($personalization.RemoveAppxPackages)) {
    $remaining = @(Get-AppxPackage -ErrorAction Stop | Where-Object { $_.Name -like $pattern -or $_.PackageFullName -like $pattern })
    if ($remaining.Count -gt 0) { throw "O pacote Appx continuou instalado para o usuario atual: $pattern" }
}
if ($removedAppx.Count -gt 0) { $actions += "AppxRemoved:$($removedAppx -join ',')" }

$knownFolderResults = @()
if ($personalization.RedirectKnownFolders -or $personalization.RestoreKnownFoldersToProfile) {
    $folderIds = Get-PcSetupKnownFolderIds
    foreach ($folderName in @($personalization.KnownFolders)) {
        $sourcePath = Get-PcSetupKnownFolderPath -Id $folderIds[$folderName]
        $targetPath = if ($personalization.RedirectKnownFolders) { Join-Path $knownFolderRoot $folderName } else { Join-Path $env:USERPROFILE $folderName }
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
        if ($personalization.CopyKnownFolderContent) { Copy-PcSetupKnownFolderContent -Source $sourcePath -Destination $targetPath }
        Set-PcSetupKnownFolderPath -Id $folderIds[$folderName] -Path $targetPath
        $confirmedPath = Get-PcSetupKnownFolderPath -Id $folderIds[$folderName]
        if ([IO.Path]::GetFullPath($confirmedPath).TrimEnd('\') -ne [IO.Path]::GetFullPath($targetPath).TrimEnd('\')) {
            throw "O Windows nao confirmou o redirecionamento de $folderName para $targetPath."
        }
        $knownFolderResults += [pscustomobject]@{ Name = $folderName; Source = $sourcePath; Target = $targetPath; OriginalContentKept = $true }
    }
    $actions += $(if ($personalization.RedirectKnownFolders) { 'KnownFoldersRedirected' } else { 'KnownFoldersRestoredToWindowsProfile' })
}

$profileLinkResult = $null
if ($personalization.ProfileLink.Enabled) {
    $profileLinkParent = [string]$configuredPaths[[string]$personalization.ProfileLink.PathKey]
    $profileLinkResult = Set-PcSetupProfileJunction -ParentPath $profileLinkParent -Name ([string]$personalization.ProfileLink.Name) -TargetPath $env:USERPROFILE
    $actions += "ProfileLink:$($profileLinkResult.Action)"
}

$googleDriveResult = $null
if ($personalization.GoogleDrive.Enabled) {
    $googleDrivePath = [string]$configuredPaths[[string]$personalization.GoogleDrive.PathKey]
    $googleDriveResult = Set-PcSetupGoogleDriveStreamingMountPoint -Path $googleDrivePath
    $actions += "GoogleDriveStreaming:$($googleDriveResult.Action)"
}

$wallpaperTarget = $null
if ($wallpaperSource) {
    Initialize-PcSetupKnownFolderApi
    $assetDirectory = Join-Path $stateRoot 'assets'
    New-Item -ItemType Directory -Path $assetDirectory -Force | Out-Null
    $wallpaperTarget = Join-Path $assetDirectory ('wallpaper' + [IO.Path]::GetExtension($wallpaperSource))
    Copy-Item -LiteralPath $wallpaperSource -Destination $wallpaperTarget -Force
    Set-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value $wallpaperTarget
    Set-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'
    Set-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0'
    if (-not [PcSetup.PersonalizationNativeMethods]::SystemParametersInfo(20, 0, $wallpaperTarget, 3)) { throw 'O Windows nao confirmou a atualizacao imediata do plano de fundo.' }
    $registeredWallpaper = [string](Get-ItemPropertyValue -LiteralPath 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction Stop)
    if ([IO.Path]::GetFullPath($registeredWallpaper) -ne [IO.Path]::GetFullPath($wallpaperTarget)) {
        throw "O registro do plano de fundo nao corresponde ao arquivo local aplicado: $registeredWallpaper"
    }
    $sourceHash = (Get-FileHash -LiteralPath $wallpaperSource -Algorithm SHA256).Hash
    $targetHash = (Get-FileHash -LiteralPath $wallpaperTarget -Algorithm SHA256).Hash
    if ($sourceHash -ne $targetHash) { throw 'A copia local do plano de fundo diverge do arquivo configurado.' }
    $actions += 'Wallpaper'
}

$explorer = Get-Process -Name explorer -ErrorAction SilentlyContinue
if ($explorer) { $explorer | Stop-Process -Force }

$result = [ordered]@{
    Step               = 'Personalization'
    Mode               = $mode
    Enabled            = $true
    User               = $env:USERNAME
    Actions            = $actions
    RemovedAppx        = $removedAppx
    PreservedAppx      = @($personalization.PreserveAppxPackages)
    KnownFolders       = $knownFolderResults
    ProfileLink        = $profileLinkResult
    GoogleDrive        = $googleDriveResult
    Wallpaper          = $wallpaperTarget
    DataRoot           = [IO.Path]::GetFullPath($DataRoot)
    WindowsApplyReport = if ($applyReport) { $WindowsApplyReport } else { $null }
    ConfigSha256       = (Get-FileHash -LiteralPath $configuration._ConfigPath -Algorithm SHA256).Hash
    ProjectSha256      = Get-PcSetupProjectFingerprint -Configuration $configuration
    CompletedAt        = (Get-Date).ToString('o')
    Action             = 'Completed'
}
$reportPath = Join-Path (Get-PcSetupRuntimePath -Configuration $configuration -Key 'UserReportDirectory') ('personalization-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
Write-PcSetupJson -InputObject $result -Path $reportPath | Out-Null
Write-Host "[RELATORIO] $reportPath" -ForegroundColor Green
[pscustomobject]$result
