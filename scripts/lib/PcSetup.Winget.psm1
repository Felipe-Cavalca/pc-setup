Set-StrictMode -Version 2.0

function ConvertTo-PcSetupWingetInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ExportObject,
        [Parameter(Mandatory)][string[]]$PackageIds,
        [Parameter(Mandatory)][string]$WingetVersion,
        [Parameter(Mandatory)][string]$ConfigSha256,
        [Parameter(Mandatory)][string]$ProjectSha256
    )

    $available = @()
    foreach ($source in @($ExportObject.Sources)) {
        $sourceIdentifier = ''
        if ($source.SourceDetails -and $source.SourceDetails.Identifier) { $sourceIdentifier = [string]$source.SourceDetails.Identifier }
        elseif ($source.SourceDetails -and $source.SourceDetails.Name) { $sourceIdentifier = [string]$source.SourceDetails.Name }
        foreach ($package in @($source.Packages)) {
            $available += [pscustomobject]@{
                PackageId = [string]$package.PackageIdentifier
                Version   = [string]$package.Version
                Source    = $sourceIdentifier
            }
        }
    }

    $records = @()
    foreach ($packageId in $PackageIds) {
        $matches = @($available | Where-Object { $_.PackageId -eq $packageId })
        if ($matches.Count -gt 1) { throw "Winget export retornou mais de uma versao para $packageId." }
        if ($matches.Count -eq 0) {
            $records += [pscustomobject]@{ PackageId = $packageId; Found = $false; Version = $null; Source = $null }
            continue
        }
        $record = $matches[0]
        $records += [pscustomobject]@{
            PackageId = $packageId
            Found     = $true
            Version   = $record.Version
            Source    = $record.Source
        }
    }

    return [pscustomobject][ordered]@{
        SchemaVersion = '1.0'
        GeneratedAt   = (Get-Date).ToString('o')
        WingetVersion = $WingetVersion
        ConfigSha256  = $ConfigSha256
        ProjectSha256 = $ProjectSha256
        Packages      = $records
    }
}

function Get-PcSetupWingetInstalledInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$PackageIds,
        [Parameter(Mandatory)][string]$ConfigSha256,
        [Parameter(Mandatory)][string]$ProjectSha256,
        [string]$WingetCommand = 'winget.exe',
        [switch]$RequireAll
    )

    $temporaryPath = Join-Path ([IO.Path]::GetTempPath()) ("pc-setup-winget-{0}.json" -f ([guid]::NewGuid().ToString('N')))
    try {
        & $WingetCommand export --output $temporaryPath --source winget --include-versions --accept-source-agreements --disable-interactivity | Out-Host
        $exportExitCode = $LASTEXITCODE
        if ($exportExitCode -ne 0 -or -not (Test-Path -LiteralPath $temporaryPath -PathType Leaf)) {
            throw "winget export falhou com codigo $exportExitCode."
        }
        $exportObject = Get-Content -LiteralPath $temporaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $wingetVersion = [string]((& $WingetCommand --version 2>$null | Select-Object -First 1))
        if ([string]::IsNullOrWhiteSpace($wingetVersion)) { $wingetVersion = 'unknown' }
        $inventory = ConvertTo-PcSetupWingetInventory -ExportObject $exportObject -PackageIds $PackageIds -WingetVersion $wingetVersion.Trim() -ConfigSha256 $ConfigSha256 -ProjectSha256 $ProjectSha256
        if ($RequireAll) {
            $missing = @($inventory.Packages | Where-Object { -not $_.Found -or [string]::IsNullOrWhiteSpace([string]$_.Version) })
            if ($missing.Count -gt 0) { throw "Winget nao informou a versao instalada de: $($missing.PackageId -join ', ')." }
        }
        return $inventory
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

Export-ModuleMember -Function ConvertTo-PcSetupWingetInventory, Get-PcSetupWingetInstalledInventory
