Set-StrictMode -Version 2.0

function Invoke-PcSetupRobocopy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Origem de backup ausente: $Source" }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    & "$env:SystemRoot\System32\robocopy.exe" $Source $Destination /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XJ /NP /NFL /NDL | Out-Host
    $exitCode = $LASTEXITCODE
    if ($exitCode -gt 7) { throw "Robocopy falhou com codigo $exitCode ao copiar $Source." }
    # Robocopy usa 1 a 7 para resultados bem-sucedidos; nao deixe esse codigo residual falhar a etapa da CI.
    $global:LASTEXITCODE = 0
    return $exitCode
}

function Get-PcSetupBackupFileRecords {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SnapshotPath)

    $root = [IO.Path]::GetFullPath($SnapshotPath).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Snapshot ausente: $root" }
    $prefix = $root + '\'
    $records = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object Name -ne 'manifest.json' | Sort-Object FullName)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Ponto de nova analise recusado no snapshot: $($file.FullName)" }
        $relative = $file.FullName.Substring($prefix.Length).Replace('\','/')
        $records += [pscustomobject][ordered]@{
            Path   = $relative
            Length = [int64]$file.Length
            Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
    }
    return $records
}

function Test-PcSetupBackupManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SnapshotPath)

    $root = [IO.Path]::GetFullPath($SnapshotPath).TrimEnd('\')
    $manifestPath = Join-Path $root 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Manifesto de backup ausente: $manifestPath" }
    try { $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Manifesto de backup invalido: $($_.Exception.Message)" }
    if ([string]$manifest.SchemaVersion -ne '1.0') { throw 'SchemaVersion do manifesto de backup nao suportada.' }

    $prefix = $root + '\'
    $seen = @()
    foreach ($record in @($manifest.Files)) {
        $relative = [string]$record.Path
        if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') { throw "Caminho inseguro no manifesto de backup: $relative" }
        $full = [IO.Path]::GetFullPath((Join-Path $root $relative.Replace('/','\')))
        if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Arquivo do manifesto sai do snapshot: $relative" }
        if ($seen -contains $relative) { throw "Arquivo duplicado no manifesto: $relative" }
        $seen += $relative
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Arquivo do backup ausente: $relative" }
        $file = Get-Item -LiteralPath $full -Force
        if ([int64]$file.Length -ne [int64]$record.Length) { throw "Tamanho divergente no backup: $relative" }
        $hash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
        if ($hash -ne [string]$record.Sha256) { throw "SHA-256 divergente no backup: $relative" }
    }
    $actual = @(Get-PcSetupBackupFileRecords -SnapshotPath $root | ForEach-Object Path)
    $unexpected = @($actual | Where-Object { $_ -notin $seen })
    if ($unexpected.Count -gt 0) { throw "O snapshot contem arquivos fora do manifesto: $($unexpected -join ', ')" }
    return [pscustomobject]@{ Valid = $true; ManifestPath = $manifestPath; Files = $seen.Count; Manifest = $manifest }
}

function Invoke-PcSetupRestoreTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SnapshotPath,
        [Parameter(Mandatory)][string]$DestinationRoot,
        [bool]$KeepRestoredCopy = $false
    )

    $source = [IO.Path]::GetFullPath($SnapshotPath).TrimEnd('\')
    $destination = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')
    if ($source -eq $destination -or $destination.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'O destino do teste de restauracao nao pode ser o snapshot nem ficar dentro dele.'
    }

    $sourceVerification = Test-PcSetupBackupManifest -SnapshotPath $source
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $testName = 'restore-test-' + (Get-Date -Format 'yyyy-MM-dd_HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $restoredPath = [IO.Path]::GetFullPath((Join-Path $destination $testName))
    $destinationPrefix = $destination + '\'
    if (-not $restoredPath.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'O destino calculado para o teste de restauracao e inseguro.' }
    if (Test-Path -LiteralPath $restoredPath) { throw "O destino temporario do teste ja existe: $restoredPath" }

    try {
        $copyExitCode = Invoke-PcSetupRobocopy -Source $source -Destination $restoredPath
        $restoredVerification = Test-PcSetupBackupManifest -SnapshotPath $restoredPath
    }
    catch {
        throw "O teste falhou; a copia restaurada foi preservada para diagnostico em $restoredPath. $($_.Exception.Message)"
    }

    $removed = $false
    if (-not $KeepRestoredCopy) {
        Remove-Item -LiteralPath $restoredPath -Recurse -Force
        $removed = $true
    }

    return [pscustomobject][ordered]@{
        Valid                     = $true
        SnapshotPath              = $source
        RestoredPath              = $restoredPath
        Files                     = $restoredVerification.Files
        CopyExitCode              = $copyExitCode
        RemovedAfterVerification  = $removed
        SourceManifest            = $sourceVerification.ManifestPath
    }
}

Export-ModuleMember -Function Invoke-PcSetupRobocopy, Get-PcSetupBackupFileRecords, Test-PcSetupBackupManifest, Invoke-PcSetupRestoreTest
