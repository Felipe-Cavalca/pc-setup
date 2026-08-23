#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\lib\PcSetup.Core.psm1') -Force

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -ne $Actual) { throw "$Message Esperado: '$Expected'. Atual: '$Actual'." }
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Message) {
    try { & $Action; throw "NAO_LANCOU: $Message" }
    catch {
        if ($_.Exception.Message -like 'NAO_LANCOU:*' -or $_.Exception.Message -notmatch $Pattern) { throw "$Message Detalhe: $($_.Exception.Message)" }
    }
}
function New-TestInventory([object[]]$Volumes, [object[]]$Disks) {
    return @{ SystemRoot = 'C:\'; SystemDriveLetter = 'C'; SystemDiskNumber = 0; Volumes = $Volumes; Disks = $Disks }
}
function New-TestVolume([string]$Drive, [int]$Disk, [bool]$Removable = $false, [string]$Health = 'Healthy', [string]$FileSystem = 'NTFS') {
    return [pscustomobject]@{ DriveLetter = $Drive; Root = "${Drive}:\"; DiskNumber = $Disk; IsRemovable = $Removable; HealthStatus = $Health; FileSystem = $FileSystem; SizeGB = 100; DiskModel = "Disk$Disk" }
}

$configuration = Import-PcSetupConfiguration -Path (Join-Path $root 'config\machine.psd1')
Assert-Equal 'Interactive' $configuration.Execution.Mode 'O perfil Felipe deve permitir a pergunta de armazenamento.'
Assert-Equal 'Ask' $configuration.Storage.Data.SecondaryDiskPolicy 'O perfil Felipe deve perguntar antes de usar o segundo disco.'
$configuration.Execution.Mode = 'Unattended'
$configuration.Storage.Data.SecondaryDiskPolicy = 'UseIfAvailable'
$systemVolume = New-TestVolume -Drive C -Disk 0
$systemDisk = [pscustomobject]@{ Number = 0; IsRemovable = $false; HealthStatus = 'Healthy' }
$dataDisk = [pscustomobject]@{ Number = 1; IsRemovable = $false; HealthStatus = 'Healthy' }

$single = Resolve-PcSetupStorage -Configuration $configuration -Inventory (New-TestInventory -Volumes @($systemVolume, (New-TestVolume -Drive D -Disk 1)) -Disks @($systemDisk, $dataDisk))
Assert-Equal 'D:\' $single.DataRoot 'Um unico segundo volume fixo deve ser usado.'
Assert-Equal 'DedicatedVolume' $single.DataMode 'O modo deve indicar volume dedicado.'

$fallback = Resolve-PcSetupStorage -Configuration $configuration -Inventory (New-TestInventory -Volumes @($systemVolume) -Disks @($systemDisk))
Assert-Equal 'C:\Dados' $fallback.DataRoot 'Sem segundo disco deve usar a pasta no volume do Windows.'

$askConfiguration = Import-PcSetupConfiguration -Path (Join-Path $root 'config\machine.psd1')
$reusedSecondDisk = Resolve-PcSetupStorage -Configuration $askConfiguration -SelectedDataRoot 'D:\' -Inventory (New-TestInventory -Volumes @($systemVolume, (New-TestVolume -Drive D -Disk 1)) -Disks @($systemDisk, $dataDisk))
Assert-Equal 'D:\' $reusedSecondDisk.DataRoot 'O Apply deve reutilizar a escolha do segundo disco feita no plano.'
$reusedFallback = Resolve-PcSetupStorage -Configuration $askConfiguration -SelectedDataRoot 'C:\Dados' -Inventory (New-TestInventory -Volumes @($systemVolume, (New-TestVolume -Drive D -Disk 1)) -Disks @($systemDisk, $dataDisk))
Assert-Equal 'C:\Dados' $reusedFallback.DataRoot 'O Apply deve reutilizar a escolha de ficar no disco do Windows.'
Assert-Throws -Pattern 'nao esta mais disponivel' -Message 'Uma escolha de disco desaparecida deve interromper.' -Action {
    Resolve-PcSetupStorage -Configuration $askConfiguration -SelectedDataRoot 'E:\' -Inventory (New-TestInventory -Volumes @($systemVolume, (New-TestVolume -Drive D -Disk 1)) -Disks @($systemDisk, $dataDisk)) | Out-Null
}

Assert-Throws -Pattern 'mais de um volume' -Message 'Multiplos candidatos devem interromper.' -Action {
    Resolve-PcSetupStorage -Configuration $configuration -Inventory (New-TestInventory -Volumes @($systemVolume, (New-TestVolume D 1), (New-TestVolume E 2)) -Disks @($systemDisk, $dataDisk, [pscustomobject]@{ Number = 2; IsRemovable = $false })) | Out-Null
}
Assert-Throws -Pattern 'nenhum volume NTFS' -Message 'Disco secundario sem volume utilizavel deve interromper.' -Action {
    Resolve-PcSetupStorage -Configuration $configuration -Inventory (New-TestInventory -Volumes @($systemVolume) -Disks @($systemDisk, $dataDisk)) | Out-Null
}

$configuration.Storage.Paths.Development = '..\fora'
Assert-Throws -Pattern 'sai da raiz' -Message 'Caminho relativo nao pode escapar da raiz de dados.' -Action {
    Get-PcSetupConfiguredPaths -Configuration $configuration -Storage $fallback | Out-Null
}
$configuration = Import-PcSetupConfiguration -Path (Join-Path $root 'config\machine.psd1')
$configuration.Storage.Paths.Development = '.'
Assert-Throws -Pattern 'propria raiz' -Message 'Nenhum diretorio configurado pode representar o volume inteiro.' -Action {
    Get-PcSetupConfiguredPaths -Configuration $configuration -Storage $fallback | Out-Null
}

$packageConfiguration = Import-PcSetupConfiguration -Path (Join-Path $root 'config\machine.psd1')
$ids = @(Get-PcSetupPackageIds -Configuration $packageConfiguration)
Assert-Equal 11 $ids.Count 'Todos os IDs dos tres perfis devem ser carregados sem duplicidade.'
Assert-Equal $true ($ids -contains 'RARLab.WinRAR') 'WinRAR deve estar no perfil base.'
$fingerprint = Get-PcSetupProjectFingerprint -Configuration $packageConfiguration
Assert-Equal 64 $fingerprint.Length 'A impressao do plano deve usar SHA-256.'
Assert-Throws -Pattern 'sai da raiz' -Message 'Arquivos auxiliares nao podem escapar do projeto.' -Action {
    Resolve-PcSetupProjectPath -Configuration $packageConfiguration -Value '..\fora.exe' -SettingName 'Teste' | Out-Null
}

Write-Host 'PASS: configuracao, armazenamento, caminhos e pacotes.' -ForegroundColor Green
