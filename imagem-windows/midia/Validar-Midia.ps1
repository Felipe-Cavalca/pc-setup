#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$MediaRoot = '',
    [string]$AnswerFile = '',
    [switch]$AnswerFileOnly,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$checks = New-Object 'Collections.Generic.List[object]'
$failures = New-Object 'Collections.Generic.List[string]'

function Add-MediaCheck {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Details
    )

    $checks.Add([pscustomobject]@{
        Verificacao = $Name
        Resultado   = if ($Passed) { 'OK' } else { 'FALHA' }
        Detalhes    = $Details
    })

    if (-not $Passed) {
        $failures.Add("${Name}: $Details")
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($MediaRoot)) {
        $MediaRoot = $PSScriptRoot
    }

    $resolvedMediaRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($MediaRoot)
    if ([string]::IsNullOrWhiteSpace($AnswerFile)) {
        $AnswerFile = Join-Path $resolvedMediaRoot 'autounattend.xml'
    }
    else {
        $AnswerFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($AnswerFile)
    }

    if (-not $AnswerFileOnly) {
        Add-MediaCheck 'setup.exe' (Test-Path -LiteralPath (Join-Path $resolvedMediaRoot 'setup.exe') -PathType Leaf) 'Arquivo de inicializacao do instalador'
        Add-MediaCheck 'boot' (Test-Path -LiteralPath (Join-Path $resolvedMediaRoot 'boot') -PathType Container) 'Diretorio de inicializacao BIOS'
        Add-MediaCheck 'efi' (Test-Path -LiteralPath (Join-Path $resolvedMediaRoot 'efi') -PathType Container) 'Diretorio de inicializacao UEFI'

        $sourcesPath = Join-Path $resolvedMediaRoot 'sources'
        Add-MediaCheck 'sources' (Test-Path -LiteralPath $sourcesPath -PathType Container) 'Arquivos da instalacao'
        $installImages = @()
        if (Test-Path -LiteralPath $sourcesPath -PathType Container) {
            $installImages = @(Get-ChildItem -LiteralPath $sourcesPath -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^install\.(wim|esd|swm)$' })
        }
        Add-MediaCheck 'Imagem do Windows' ($installImages.Count -gt 0) (($installImages.Name | Sort-Object) -join ', ')

        $legacyInstallers = Join-Path $resolvedMediaRoot 'Installers'
        $hasLegacyInstallerDirectory = Test-Path -LiteralPath $legacyInstallers -PathType Container
        Add-MediaCheck 'Sem pasta Installers antiga' (-not $hasLegacyInstallerDirectory) $(if ($hasLegacyInstallerDirectory) { $legacyInstallers } else { 'Ausente' })
    }

    if (-not (Test-Path -LiteralPath $AnswerFile -PathType Leaf)) {
        if ($AnswerFileOnly) {
            Add-MediaCheck 'Arquivo de resposta' $false "Nao encontrado: $AnswerFile"
        }
        else {
            Add-MediaCheck 'Arquivo de resposta' $true 'Ausente; o instalador exibira todas as telas padrao'
        }
    }
    else {
        try {
            [xml]$answerXml = Get-Content -LiteralPath $AnswerFile -Raw -Encoding UTF8
            Add-MediaCheck 'XML bem formado' $true $AnswerFile

            $rootIsUnattend = $answerXml.DocumentElement.LocalName -eq 'unattend' -and $answerXml.DocumentElement.NamespaceURI -eq 'urn:schemas-microsoft-com:unattend'
            Add-MediaCheck 'Raiz do arquivo de resposta' $rootIsUnattend 'Namespace oficial do Windows Setup'

            $forbiddenNodes = @(
                'DiskConfiguration',
                'ImageInstall',
                'UserAccounts',
                'AutoLogon',
                'Password',
                'ProductKey',
                'RunSynchronous',
                'RunAsynchronous',
                'FirstLogonCommands',
                'Extensions'
            )

            foreach ($nodeName in $forbiddenNodes) {
                $count = @($answerXml.SelectNodes("//*[local-name()='$nodeName']")).Count
                Add-MediaCheck "Ausencia de $nodeName" ($count -eq 0) "$count ocorrencia(s)"
            }

            $allowedComponents = @(
                'Microsoft-Windows-International-Core-WinPE',
                'Microsoft-Windows-International-Core'
            )
            $componentNames = @($answerXml.SelectNodes("//*[local-name()='component']") | ForEach-Object { $_.GetAttribute('name') })
            $unexpectedComponents = @($componentNames | Where-Object { $_ -notin $allowedComponents })
            Add-MediaCheck 'Somente componentes de idioma' ($unexpectedComponents.Count -eq 0) (($componentNames | Sort-Object -Unique) -join ', ')

            $localeValues = @($answerXml.SelectNodes("//*[local-name()='InputLocale' or local-name()='SystemLocale' or local-name()='UILanguage' or local-name()='UserLocale']") | ForEach-Object { $_.InnerText })
            $unexpectedLocales = @($localeValues | Where-Object { $_ -notin @('pt-BR', '0416:00000416') })
            Add-MediaCheck 'Localidade pt-BR' ($localeValues.Count -gt 0 -and $unexpectedLocales.Count -eq 0) (($localeValues | Sort-Object -Unique) -join ', ')

            $hash = (Get-FileHash -LiteralPath $AnswerFile -Algorithm SHA256).Hash
            Add-MediaCheck 'SHA-256 do arquivo de resposta' $true $hash
        }
        catch {
            Add-MediaCheck 'XML bem formado' $false $_.Exception.Message
        }
    }
}
catch {
    Add-MediaCheck 'Execucao do validador' $false $_.Exception.Message
}

Write-Host "`nValidacao da midia" -ForegroundColor Cyan
$checks | Format-Table -AutoSize -Wrap

if ($failures.Count -gt 0) {
    Write-Host "Resultado: FALHA ($($failures.Count) erro(s))" -ForegroundColor Red
    $exitCode = 1
}
else {
    Write-Host 'Resultado: OK' -ForegroundColor Green
    $exitCode = 0
}

if (-not $NoPause) {
    [void](Read-Host 'Pressione ENTER para fechar')
}

exit $exitCode
