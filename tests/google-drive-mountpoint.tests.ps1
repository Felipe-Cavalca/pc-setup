#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$personalizationPath = Join-Path $root 'scripts\80-personalization.ps1'
$configuration = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'config\machine.psd1')

function Assert-True($Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}

Assert-True ($configuration.Personalization.GoogleDrive.RequireConfiguredMountPoint -eq $false) 'O perfil padrao deve permitir Google Drive ainda nao inicializado.'

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($personalizationPath, [ref]$tokens, [ref]$parseErrors)
Assert-True (@($parseErrors).Count -eq 0) '80-personalization.ps1 deve permanecer sintaticamente valido.'
$functionAst = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Get-PcSetupGoogleDriveStreamingMountPointState'
}, $true)
Assert-True ($null -ne $functionAst) 'A validacao do DefaultMountPoint deve existir como funcao testavel.'
Invoke-Expression ('function Get-PcSetupGoogleDriveStreamingMountPointState ' + $functionAst.Body.Extent.Text)

$testId = [guid]::NewGuid().ToString('N')
$registryRoot = "HKCU:\Software\pc-setup-tests\$testId"
$registryPath = Join-Path $registryRoot 'DriveFS'
$mountPoint = Join-Path $env:TEMP "pc-setup-google-drive-$testId"
$otherMountPoint = "$mountPoint-other"
New-Item -ItemType Directory -Path $mountPoint -Force | Out-Null
New-Item -ItemType Directory -Path $otherMountPoint -Force | Out-Null

try {
    # Chave ausente: pendencia nao fatal e nenhuma mutacao do Registro.
    $missingKey = Get-PcSetupGoogleDriveStreamingMountPointState -Path $mountPoint -RegistryPath $registryPath
    Assert-True ($missingKey.Status -eq 'PendingManual' -and $missingKey.State -eq 'RegistryKeyMissing') 'Chave DriveFS ausente deve virar PendingManual.'
    Assert-True (-not (Test-Path -LiteralPath $registryPath)) 'A validacao nao deve criar a chave DriveFS ausente.'
    Assert-True ($missingKey.Instruction -match 'Abra o Google Drive') 'A pendencia deve orientar a inicializacao/configuracao do Google Drive.'

    # Chave presente sem DefaultMountPoint: tambem pendencia nao fatal.
    New-Item -Path $registryPath -Force | Out-Null
    $missingProperty = Get-PcSetupGoogleDriveStreamingMountPointState -Path $mountPoint -RegistryPath $registryPath
    Assert-True ($missingProperty.Status -eq 'PendingManual' -and $missingProperty.State -eq 'DefaultMountPointMissing') 'Propriedade ausente deve virar PendingManual.'
    $settings = Get-ItemProperty -LiteralPath $registryPath
    Assert-True ($null -eq $settings.PSObject.Properties['DefaultMountPoint']) 'A validacao nao deve criar DefaultMountPoint.'

    # Valor presente e igual ao esperado: configuracao valida.
    New-ItemProperty -LiteralPath $registryPath -Name DefaultMountPoint -PropertyType String -Value $mountPoint -Force | Out-Null
    $configured = Get-PcSetupGoogleDriveStreamingMountPointState -Path $mountPoint -RegistryPath $registryPath
    Assert-True ($configured.Status -eq 'Configured' -and $configured.State -eq 'Configured') 'Mount point esperado deve ser aceito.'
    Assert-True ($configured.CurrentValue -eq $mountPoint) 'O relatorio deve preservar o valor observado.'

    # Valor sintaticamente invalido: falha fechada sem sobrescrever.
    Set-ItemProperty -LiteralPath $registryPath -Name DefaultMountPoint -Value 'relative\mount'
    $invalidRejected = $false
    try { Get-PcSetupGoogleDriveStreamingMountPointState -Path $mountPoint -RegistryPath $registryPath | Out-Null }
    catch { $invalidRejected = $_.Exception.Message -match 'invalido|nao suportado' }
    Assert-True $invalidRejected 'DefaultMountPoint invalido deve ser rejeitado com diagnostico seguro.'
    Assert-True ((Get-ItemPropertyValue -LiteralPath $registryPath -Name DefaultMountPoint) -eq 'relative\mount') 'Valor invalido nao pode ser sobrescrito.'

    # Valor valido, mas apontando para outro local: incompatibilidade deve bloquear.
    Set-ItemProperty -LiteralPath $registryPath -Name DefaultMountPoint -Value $otherMountPoint
    $mismatchRejected = $false
    try { Get-PcSetupGoogleDriveStreamingMountPointState -Path $mountPoint -RegistryPath $registryPath | Out-Null }
    catch { $mismatchRejected = $_.Exception.Message -match 'espera' -and $_.Exception.Message -match 'preservado' }
    Assert-True $mismatchRejected 'Mount point valido mas incompatível deve ser rejeitado sem alteracao.'
    Assert-True ((Get-ItemPropertyValue -LiteralPath $registryPath -Name DefaultMountPoint) -eq $otherMountPoint) 'Mount point incompatível deve ser preservado.'

    # Ausencia vira falha somente quando a configuracao a torna obrigatoria.
    Remove-ItemProperty -LiteralPath $registryPath -Name DefaultMountPoint -Force
    $requiredRejected = $false
    try { Get-PcSetupGoogleDriveStreamingMountPointState -Path $mountPoint -RegistryPath $registryPath -RequireConfiguredMountPoint $true | Out-Null }
    catch { $requiredRejected = $_.Exception.Message -match 'RequireConfiguredMountPoint' }
    Assert-True $requiredRejected 'RequireConfiguredMountPoint deve transformar a ausencia em falha fechada.'
}
finally {
    if (Test-Path -LiteralPath $registryRoot) { Remove-Item -LiteralPath $registryRoot -Recurse -Force -ErrorAction SilentlyContinue }
    foreach ($path in @($mountPoint, $otherMountPoint)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item -Path Function:\Get-PcSetupGoogleDriveStreamingMountPointState -ErrorAction SilentlyContinue
}

Write-Host 'PASS: estados do DefaultMountPoint do Google Drive tratados com seguranca.' -ForegroundColor Green
