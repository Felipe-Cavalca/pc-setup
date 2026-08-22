Set-StrictMode -Version 2.0

function Resolve-PcSetupWslTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Configuration,
        [string]$EnvironmentName = '',
        [string]$CurrentWindowsAccount = $env:USERNAME
    )

    $environments = @(Get-PcSetupWslEnvironments -Configuration $Configuration | Where-Object Enabled)
    if ([string]::IsNullOrWhiteSpace($EnvironmentName)) {
        $matches = @($environments | Where-Object { $_.WindowsAccount -eq $CurrentWindowsAccount })
        if ($matches.Count -ne 1) { throw "Nao foi possivel selecionar um ambiente WSL para o usuario Windows $CurrentWindowsAccount. Informe -Environment." }
        $environment = $matches[0]
    }
    else {
        $environment = $environments | Where-Object { $_.Name -eq $EnvironmentName } | Select-Object -First 1
        if (-not $environment) { throw "Ambiente WSL habilitado nao encontrado: $EnvironmentName" }
    }
    $profile = Import-PcSetupWslProfile -Configuration $Configuration -Environment $environment
    return [pscustomobject]@{ Environment = $environment; Profile = $profile }
}

function Get-PcSetupWslDistributionNames {
    [CmdletBinding()]
    param([string]$WslCommand = 'wsl.exe')

    $output = @(& $WslCommand --list --quiet 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "wsl --list --quiet falhou com codigo $LASTEXITCODE." }
    return @($output | ForEach-Object { ([string]$_).Replace([char]0, '').Trim() } | Where-Object { $_ })
}

function Get-PcSetupWslDistributionVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [string]$WslCommand = 'wsl.exe'
    )

    $output = @(& $WslCommand --list --verbose 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "wsl --list --verbose falhou com codigo $LASTEXITCODE." }
    $escaped = [regex]::Escape($Distribution)
    foreach ($line in $output) {
        $clean = ([string]$line).Replace([char]0, '')
        if ($clean -match "^\s*\*?\s*$escaped\s+\S+\s+(\d+)\s*$") { return [int]$Matches[1] }
    }
    return $null
}

function Get-PcSetupWslDefaultUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [string]$WslCommand = 'wsl.exe'
    )

    $output = @(& $WslCommand --distribution $Distribution -- id --user --name 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) { throw "Nao foi possivel consultar o usuario padrao de $Distribution." }
    return ([string]$output[-1]).Replace([char]0, '').Trim()
}

function ConvertTo-PcSetupWslPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$WindowsPath,
        [string]$WslCommand = 'wsl.exe'
    )

    $output = @(& $WslCommand --distribution $Distribution --user root -- wslpath -a $WindowsPath 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) { throw "Nao foi possivel converter o caminho para WSL: $WindowsPath" }
    return ([string]$output[-1]).Replace([char]0, '').Trim()
}

function Invoke-PcSetupWslLinuxScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)]$Environment,
        [Parameter(Mandatory)][hashtable]$Profile,
        [string]$WslCommand = 'wsl.exe'
    )

    $arguments = @(
        '--profile-name', [string]$Environment.Name,
        '--linux-user', [string]$Profile.LinuxUser,
        '--project-root', [string]$Profile.ProjectRoot
    )
    foreach ($package in @($Profile.Packages)) { $arguments += @('--package', [string]$package) }
    $output = @(& $WslCommand --distribution $Distribution --user root -- bash $ScriptPath @arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $output | Out-Host
    return [pscustomobject]@{ ExitCode = $exitCode; Output = @($output | ForEach-Object { [string]$_ }) }
}

Export-ModuleMember -Function Resolve-PcSetupWslTarget, Get-PcSetupWslDistributionNames, Get-PcSetupWslDistributionVersion, Get-PcSetupWslDefaultUser, ConvertTo-PcSetupWslPath, Invoke-PcSetupWslLinuxScript
