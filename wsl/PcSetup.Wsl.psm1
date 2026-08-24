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
        if ($matches.Count -eq 1) { $environment = $matches[0] }
        else {
            $defaults = @($matches | Where-Object Default)
            if ($defaults.Count -ne 1) { throw "Nao foi possivel selecionar um ambiente WSL para o usuario Windows $CurrentWindowsAccount. Informe -Environment." }
            $environment = $defaults[0]
        }
    }
    else {
        $environment = $environments | Where-Object { $_.Name -eq $EnvironmentName } | Select-Object -First 1
        if (-not $environment) { throw "Ambiente WSL habilitado nao encontrado: $EnvironmentName" }
    }
    $profile = Import-PcSetupWslProfile -Configuration $Configuration -Environment $environment
    return [pscustomobject]@{ Environment = $environment; Profile = $profile }
}

function Get-PcSetupExpectedWslDefaultUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Configuration,
        [Parameter(Mandatory)]$Environment
    )

    $defaultEnvironment = Get-PcSetupWslEnvironments -Configuration $Configuration |
        Where-Object {
            $_.Enabled -and $_.Default -and
            $_.WindowsAccount -eq $Environment.WindowsAccount -and
            $_.Distribution -eq $Environment.Distribution
        } |
        Select-Object -First 1
    if (-not $defaultEnvironment) { throw "Ambiente WSL padrao ausente para $($Environment.WindowsAccount)/$($Environment.Distribution)." }
    return [string](Import-PcSetupWslProfile -Configuration $Configuration -Environment $defaultEnvironment).LinuxUser
}

function Get-PcSetupWslDistributionNames {
    [CmdletBinding()]
    param([string]$WslCommand = 'wsl.exe')

    $output = @(& $WslCommand --list --quiet 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "wsl --list --quiet falhou com codigo $LASTEXITCODE." }
    return @($output | ForEach-Object { ([string]$_).Replace([string][char]0, [string]::Empty).Trim() } | Where-Object { $_ })
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
        $clean = ([string]$line).Replace([string][char]0, [string]::Empty)
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

    $output = @(& $WslCommand --distribution $Distribution --exec id --user --name 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) { throw "Nao foi possivel consultar o usuario padrao de $Distribution." }
    return ([string]$output[-1]).Replace([string][char]0, [string]::Empty).Trim()
}

function ConvertTo-PcSetupWslPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$WindowsPath,
        [string]$WslCommand = 'wsl.exe'
    )

    # --exec evita que o shell Linux interprete as barras invertidas do caminho Windows.
    $output = @(& $WslCommand --distribution $Distribution --user root --exec wslpath -a -- $WindowsPath 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) { throw "Nao foi possivel converter o caminho para WSL: $WindowsPath" }
    return ([string]$output[-1]).Replace([string][char]0, [string]::Empty).Trim()
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
        '--project-root', [string]$Profile.ProjectRoot,
        '--project-root-mode', [string]$Profile.ProjectRootMode,
        '--set-default-user', ([string][bool]$Profile.SetAsDefaultUser).ToLowerInvariant(),
        '--require-no-sudo', ([string][bool]$Profile.RequireNoSudo).ToLowerInvariant()
    )
    foreach ($package in @($Profile.Packages)) { $arguments += @('--package', [string]$package) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Profile.SharedGroup)) { $arguments += @('--shared-group', [string]$Profile.SharedGroup) }
    foreach ($sharedUser in @($Profile.SharedWith)) { $arguments += @('--shared-with', [string]$sharedUser) }
    if ($Profile.ContainsKey('AiJail') -and $Profile.AiJail.Enabled) {
        $arguments += @(
            '--ai-jail-repository', [string]$Profile.AiJail.Repository,
            '--ai-jail-version', [string]$Profile.AiJail.Version,
            '--ai-jail-architecture', [string]$Profile.AiJail.Architecture,
            '--ai-jail-sha256', [string]$Profile.AiJail.Sha256,
            '--ai-jail-require-asset-digest', ([string][bool]$Profile.AiJail.RequireAssetDigest).ToLowerInvariant()
        )
    }
    if ($Profile.ContainsKey('AiMemory') -and $Profile.AiMemory.Enabled) {
        $arguments += @(
            '--ai-memory-repository', [string]$Profile.AiMemory.Repository,
            '--ai-memory-version', [string]$Profile.AiMemory.Version,
            '--ai-memory-architecture', [string]$Profile.AiMemory.Architecture,
            '--ai-memory-sha256', [string]$Profile.AiMemory.Sha256,
            '--ai-memory-require-asset-digest', ([string][bool]$Profile.AiMemory.RequireAssetDigest).ToLowerInvariant(),
            '--ai-memory-client', [string]$Profile.AiMemory.Client,
            '--ai-memory-project-strategy', [string]$Profile.AiMemory.ProjectStrategy,
            '--ai-memory-server-url', [string]$Profile.AiMemory.ServerUrl
        )
    }
    if ($Profile.ContainsKey('Harness') -and $Profile.Harness.Enabled) {
        $arguments += @(
            '--harness-command', [string]$Profile.Harness.Command,
            '--harness-package', [string]$Profile.Harness.Package,
            '--harness-version', [string]$Profile.Harness.Version
        )
    }
    $output = @(& $WslCommand --distribution $Distribution --user root --exec bash -- $ScriptPath @arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $output | Out-Host
    return [pscustomobject]@{ ExitCode = $exitCode; Output = @($output | ForEach-Object { [string]$_ }) }
}

function Get-PcSetupWslInstalledState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$ProfileName,
        [string]$WslCommand = 'wsl.exe'
    )

    if ($ProfileName -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "Nome de perfil WSL invalido: $ProfileName" }
    $manifestPath = "/var/lib/pc-setup/$ProfileName/installed.tsv"
    $lines = @(& $WslCommand --distribution $Distribution --user root --exec cat -- $manifestPath 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Manifesto WSL ausente ou ilegivel: $manifestPath" }
    $metadata = [ordered]@{}
    $packages = @()
    foreach ($rawLine in $lines) {
        $line = ([string]$rawLine).Replace([string][char]0, [string]::Empty)
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t", 2
        $key = $parts[0]
        $value = if ($parts.Count -eq 2) { $parts[1] } else { '' }
        if ($key.StartsWith('package=')) {
            $packages += [pscustomobject]@{ Name = $key.Substring(8); Version = $value }
        }
        elseif ($key.Contains('=')) {
            $pair = $key -split '=', 2
            $metadata[$pair[0]] = $pair[1]
        }
        else {
            $metadata[$key] = $value
        }
    }
    return [pscustomobject]@{ ManifestPath = $manifestPath; Metadata = $metadata; Packages = $packages }
}

Export-ModuleMember -Function Resolve-PcSetupWslTarget, Get-PcSetupExpectedWslDefaultUser, Get-PcSetupWslDistributionNames, Get-PcSetupWslDistributionVersion, Get-PcSetupWslDefaultUser, ConvertTo-PcSetupWslPath, Invoke-PcSetupWslLinuxScript, Get-PcSetupWslInstalledState
