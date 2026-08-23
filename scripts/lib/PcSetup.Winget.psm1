Set-StrictMode -Version 2.0

function ConvertTo-PcSetupWingetInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ExportObject,
        [Parameter(Mandatory)][string[]]$PackageIds,
        [Parameter(Mandatory)][string]$WingetVersion,
        [Parameter(Mandatory)][string]$ConfigSha256,
        [Parameter(Mandatory)][string]$ProjectSha256,
        [ValidateSet('machine','user')][string]$InstallScope = 'machine',
        [hashtable]$InstallScopes = @{}
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
        $scope = if ($InstallScopes.ContainsKey($packageId)) { [string]$InstallScopes[$packageId] } else { $InstallScope }
        if ($scope -notin @('machine','user')) { throw "Escopo Winget invalido para ${packageId}: $scope" }
        $matches = @($available | Where-Object { $_.PackageId -eq $packageId })
        if ($matches.Count -gt 1) { throw "Winget export retornou mais de uma versao para $packageId." }
        if ($matches.Count -eq 0) {
            $records += [pscustomobject]@{ PackageId = $packageId; Scope = $scope; Found = $false; Version = $null; Source = $null }
            continue
        }
        $record = $matches[0]
        $records += [pscustomobject]@{
            PackageId = $packageId
            Scope     = $scope
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
        InstallScope  = $(if ($InstallScopes.Count -gt 0) { 'per-package' } else { $InstallScope })
        Packages      = $records
    }
}

function Get-PcSetupWingetInstalledInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$PackageIds,
        [Parameter(Mandatory)][string]$ConfigSha256,
        [Parameter(Mandatory)][string]$ProjectSha256,
        [ValidateSet('machine','user')][string]$InstallScope = 'machine',
        [hashtable]$InstallScopes = @{},
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
        $inventory = ConvertTo-PcSetupWingetInventory -ExportObject $exportObject -PackageIds $PackageIds -WingetVersion $wingetVersion.Trim() -ConfigSha256 $ConfigSha256 -ProjectSha256 $ProjectSha256 -InstallScope $InstallScope -InstallScopes $InstallScopes
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
