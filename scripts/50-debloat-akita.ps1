#requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# O Win-Debloat-Tools citado originalmente pelo Akita foi arquivado.
# Para Windows 11 atual usamos o sucessor mantido Win11Debloat, do Raphire,
# fixado em uma release estavel em vez de executar uma URL flutuante.
$repo = 'Raphire/Win11Debloat'
$release = '2026.07.11'
$targetWindows = '25H2'
$minimumBuild = 26200

$windows = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$displayVersion = $windows.DisplayVersion
$currentBuild = [int]$windows.CurrentBuildNumber

Write-Host "Windows detectado: $displayVersion (build $currentBuild)"
Write-Host "Target deste setup: Windows 11 Pro $targetWindows (build >= $minimumBuild)"
Write-Host "Debloat: $repo release $release"

if ($currentBuild -lt $minimumBuild) {
    throw "Este setup de debloat foi preparado para Windows 11 25H2/build 26200 ou posterior. Build atual: $currentBuild."
}

# Win11Debloat 2026.07.11 exige Windows PowerShell 5.1 e recusa PowerShell 7.
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Write-Host '[RELAUNCH] Abrindo o script no Windows PowerShell 5.1...'
    $process = Start-Process -FilePath $windowsPowerShell -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`""
    ) -Wait -PassThru
    exit $process.ExitCode
}

$workRoot = Join-Path $env:TEMP "pc-setup-win11debloat-$release"
$zip = "$workRoot.zip"
$url = "https://github.com/$repo/archive/refs/tags/$release.zip"

Remove-Item $workRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zip -Force -ErrorAction SilentlyContinue

Write-Host '[DOWNLOAD] Baixando release fixa do Win11Debloat...'
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
Expand-Archive -Path $zip -DestinationPath $workRoot -Force

$script = Get-ChildItem $workRoot -Recurse -Filter 'Win11Debloat.ps1' | Select-Object -First 1
if (-not $script) {
    throw 'Win11Debloat.ps1 nao encontrado no pacote baixado.'
}

Get-ChildItem $script.Directory.FullName -Recurse -File | Unblock-File

Write-Host '[RUN] Aplicando o preset padrao automaticamente...'
Write-Host '      - cria restore point/backup de registry quando suportado'
Write-Host '      - remove a selecao padrao de bloatware'
Write-Host '      - desativa telemetria, sugestoes, Copilot/Recall e outros defaults'
Write-Host '      - NAO usa -RemoveGamingApps; Xbox/Gaming modernos nao sao removidos por esse parametro'

Push-Location $script.Directory.FullName
try {
    & $script.FullName -RunDefaults -Silent -CreateRestorePoint
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "Win11Debloat terminou com codigo $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

Write-Host '[OK] Debloat concluido. Reinicie o Windows antes de validar o setup.' -ForegroundColor Green
